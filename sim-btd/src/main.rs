//! App-sim transport: the same `btd` session, over a WebSocket.
//!
//! iOS Simulator has no Bluetooth, and there is no duck on the desk. This process is the
//! pipe a phone-shaped web app talks to instead. It does not own wifi, health or updates —
//! it forwards, exactly as `btd` does. See `docs/app-demo/SIM-DUCK.md`.

use std::path::PathBuf;

use btd::link::Link;
use btd::session;
use btd::upstream::Sockets;
use clap::Parser;
use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, UnixListener, UnixStream};
use tokio_tungstenite::tungstenite::Message;

#[derive(Parser, Debug)]
#[command(
    version,
    about = "WebSocket transport adapter for the robot API (App-sim)",
    long_about = "Serves the same routed JSON-RPC subset as btd, over ws:// instead of GATT. \
                  Laptop and harness only."
)]
struct Args {
    #[arg(long, default_value = "127.0.0.1:17432")]
    listen: String,

    #[arg(long, default_value = duck_ipc_proto::socket::UPDATER)]
    update_socket: PathBuf,

    #[arg(long, default_value = duck_ipc_proto::socket::ROBOT)]
    robot_socket: PathBuf,

    #[arg(long, default_value = duck_ipc_proto::socket::CONFIG)]
    config_socket: PathBuf,

    /// Serve a local updater stub on `--update-socket`.
    ///
    /// Real `updaterd` wants a board config and a release store. The stub answers `hello`,
    /// `update.status`, `update.check` and `update.listInstalled` with canned values, and
    /// refuses apply/rollback/select by name rather than inventing a download.
    #[arg(long)]
    stub_updater: bool,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .with_writer(std::io::stderr)
        .init();

    let args = Args::parse();
    duck_ipc_proto::log_startup_identity!("sim-btd");

    if args.stub_updater {
        let path = args.update_socket.clone();
        tokio::spawn(async move {
            if let Err(e) = serve_updater_stub(path).await {
                tracing::error!(error = %e, "updater stub failed");
            }
        });
        // The listener must exist before the first hello.
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    }

    let sockets = Sockets {
        updater: args.update_socket,
        robot: args.robot_socket,
        config: args.config_socket,
    };

    let listener = TcpListener::bind(&args.listen)
        .await
        .unwrap_or_else(|e| panic!("cannot listen on {}: {e}", args.listen));
    tracing::info!(listen = %args.listen, "serving App-sim WebSocket");

    loop {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {
                tracing::info!("shutting down");
                break;
            }
            accepted = listener.accept() => {
                let Ok((stream, peer)) = accepted else { continue };
                let sockets = sockets.clone();
                tokio::spawn(async move {
                    if let Err(e) = serve_client(stream, peer.to_string(), sockets).await {
                        tracing::warn!(peer = %peer, error = %e, "session ended");
                    }
                });
            }
        }
    }
}

async fn serve_client(
    stream: tokio::net::TcpStream,
    peer: String,
    sockets: Sockets,
) -> Result<(), String> {
    let ws = tokio_tungstenite::accept_async(stream)
        .await
        .map_err(|e| e.to_string())?;
    let (mut sink, mut incoming) = ws.split();

    // Large enough that one JSON-RPC line is one chunk. The session still frames;
    // we just do not pretend this is a 20-byte ATT payload.
    let (link, to_robot, mut from_robot) = Link::pair(4096, peer.clone());
    tokio::spawn(session::run(link, sockets));

    loop {
        tokio::select! {
            msg = incoming.next() => {
                let Some(msg) = msg else { break };
                let msg = msg.map_err(|e| e.to_string())?;
                let bytes = match msg {
                    Message::Text(text) => text.as_bytes().to_vec(),
                    Message::Binary(bin) => bin.to_vec(),
                    Message::Ping(_) | Message::Pong(_) => continue,
                    Message::Close(_) => break,
                    Message::Frame(_) => continue,
                };
                let mut chunk = bytes;
                if !chunk.ends_with(&[b'\n']) {
                    chunk.push(b'\n');
                }
                if to_robot.send(chunk).await.is_err() {
                    break;
                }
            }
            chunk = from_robot.recv() => {
                let Some(chunk) = chunk else { break };
                let text = String::from_utf8_lossy(&chunk).into_owned();
                if sink.send(Message::Text(text.into())).await.is_err() {
                    break;
                }
            }
        }
    }
    Ok(())
}

async fn serve_updater_stub(path: PathBuf) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    tracing::info!(socket = %path.display(), "updater stub listening");
    loop {
        let (stream, _) = listener.accept().await.map_err(|e| e.to_string())?;
        tokio::spawn(async move {
            if let Err(e) = handle_updater_conn(stream).await {
                tracing::debug!(error = %e, "updater stub connection closed");
            }
        });
    }
}

async fn handle_updater_conn(stream: UnixStream) -> Result<(), String> {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();
    while let Some(line) = lines.next_line().await.map_err(|e| e.to_string())? {
        let request: duck_ipc_proto::Request =
            serde_json::from_str(&line).map_err(|e| e.to_string())?;
        let id = request.id.clone();
        let reply = match request.as_call() {
            Ok(call) => stub_reply(id, &call),
            Err(e) => duck_ipc_proto::Response::err(id, e),
        };
        let mut out = serde_json::to_string(&reply).map_err(|e| e.to_string())?;
        out.push('\n');
        writer
            .write_all(out.as_bytes())
            .await
            .map_err(|e| e.to_string())?;
        writer.flush().await.map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn stub_reply(
    id: Option<duck_ipc_proto::Id>,
    call: &duck_ipc_proto::Call,
) -> duck_ipc_proto::Response {
    use duck_ipc_proto::{
        API_VERSION, Call, CheckResult, ComponentId, ComponentStatus, HelloResult, InstalledRelease,
        Phase,
    };

    let daemon = ComponentId("daemon".into());
    let installed = semver::Version::parse("0.10.0").expect("literal");
    let candidate = semver::Version::parse("0.11.0").expect("literal");

    match call {
        Call::Hello(_) => duck_ipc_proto::Response::ok(
            id,
            &HelloResult {
                api_version: API_VERSION,
                daemon_version: semver::Version::parse(env!("CARGO_PKG_VERSION")).ok(),
                revision: None,
            },
        ),
        Call::Status => duck_ipc_proto::Response::ok(
            id,
            &vec![ComponentStatus {
                component: daemon,
                installed: Some(installed),
                phase: Phase::Idle,
                healthy: Some(true),
                pinned: None,
                last_attempt: None,
            }],
        ),
        Call::Check(_) => duck_ipc_proto::Response::ok(
            id,
            &CheckResult::Available {
                installed: Some(installed),
                candidate,
                mandatory: false,
                changelog: Some(
                    "模拟环境不下载制品。真鸭子上，点更新会让它用自己的 Wi-Fi 去拉签名包。"
                        .into(),
                ),
            },
        ),
        Call::ListInstalled(_) => duck_ipc_proto::Response::ok(
            id,
            &vec![InstalledRelease {
                version: installed,
                active: true,
                golden: true,
                source_revision: Some("app-sim".into()),
            }],
        ),
        Call::Log(_) => duck_ipc_proto::Response::ok(id, &Vec::<duck_ipc_proto::LogEntry>::new()),
        Call::Apply(_) | Call::Rollback(_) | Call::Select(_) | Call::Subscribe | Call::Show(_) => {
            duck_ipc_proto::Response::err(
                id,
                duck_ipc_proto::Error::new(
                    duck_ipc_proto::code::INTERNAL_ERROR,
                    "sim updater does not apply releases; point MICRODUCK_TRANSPORT=ble at a real duck",
                ),
            )
        }
        other => duck_ipc_proto::Response::err(
            id,
            duck_ipc_proto::Error::new(
                duck_ipc_proto::code::METHOD_NOT_FOUND,
                format!("{} is not served by the App-sim updater stub", other.method()),
            ),
        ),
    }
}
