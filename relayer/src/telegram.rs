use teloxide::prelude::*;
use teloxide::types::ChatId;
use teloxide::types::MessageId;
use teloxide::types::ThreadId;
use tokio::sync::mpsc;

pub async fn run_log_forwarder(
    mut logs: mpsc::Receiver<String>,
    config: crate::config::TelegramConfig,
) {
    let bot = Bot::new(config.token);

    let chat_id = ChatId(config.chat_id.parse::<i64>().unwrap());
    let topic_id = ThreadId(MessageId(config.topic_id.parse::<i32>().unwrap()));

    while let Some(log) = logs.recv().await {
        let log = if log.contains("WARN") || log.contains("ERROR") {
            format!("{} {}", config.critical_prefix, log)
        } else {
            log
        };

        if let Err(e) = bot
            .send_message(chat_id, log)
            .message_thread_id(topic_id)
            .await
        {
            eprintln!("Failed to send message: {:?}", e);
        }
    }
}
