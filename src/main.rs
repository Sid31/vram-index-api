use anyhow::Result;
use chrono::{DateTime, Utc};
use dotenv::dotenv;
use log::{error, info, LevelFilter};
use log4rs;
use log4rs::append::file::FileAppender;
use log4rs::config::{Appender, Config, Logger, Root as LogRoot};
use std::env;
use sui_sdk::{
    rpc_types::{SuiEvent, EventFilter},
    types::base_types::ObjectID,
    SuiClientBuilder,
};
use surrealdb::{
    engine::remote::ws::{Client, Ws},
    opt::auth::Root,
    sql::Thing,
    Surreal,
};
use serde::{Deserialize, Serialize};
use futures::StreamExt;
use bcs;

// Event structs
#[derive(Debug, Deserialize, Serialize)]
struct TokensPurchased {
    buyer: String,
    amount: u64,
    timestamp: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct TokensTransferred {
    from: String,
    to: String,
    amount: u64,
    timestamp: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct PriceUpdate {
    new_price: u64,
    tokens_sold: u64,
    timestamp: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct LiquidityDeployed {
    launchpad_id: String,
    sui_amount: u64,
    timestamp: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct PoolPaused {
    launchpad_id: String,
    timestamp: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct PoolUnpaused {
    launchpad_id: String,
    timestamp: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct LaunchpadCreated {
    launchpad_id: String,
    creator: String,
    name: String,
    description: String,
    token_supply: u64,
    initial_price: u64,
    price_increment: u64,
    website_url: String,
    timestamp: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct VestingClaimed {
    user: String,
    amount: u64,
    timestamp: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct FeeUpdated {
    previous_fee: u64,
    new_fee: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct AdminTransferred {
    previous_admin: String,
    new_admin: String,
}

#[derive(Debug, Deserialize, Serialize)]
struct BalanceUpdate {
    launchpad_id: String,
    holder: String,
    balance: u64,
    timestamp: u64,
}

// Database records
#[derive(Debug, Serialize, Deserialize)]
struct Transaction {
    transaction_type: String,
    timestamp: i64,
    tx_digest: String,
}

#[derive(Debug, Deserialize, Serialize)]
struct Holder {
    id: Option<Thing>,
    wallet_address: String,
    balance: u64,
    last_updated: DateTime<Utc>,
}

struct Indexer {
    package_id: ObjectID,
    db: Surreal<Client>,
}

impl Indexer {
    async fn new(package_id: &str) -> Result<Self> {
        info!("Initializing Indexer with package ID: {}", package_id);
        
        // Create database connection
        let db = Surreal::new::<Ws>("127.0.0.1:8000").await?;
        db.signin(Root {
            username: "root",
            password: "root",
        })
        .await?;
        db.use_ns("sui").use_db("launchpad").await?;

        // Create tables if they don't exist
        db.query("DEFINE TABLE token_purchases SCHEMAFULL").await?;
        db.query("DEFINE FIELD buyer ON token_purchases TYPE string").await?;
        db.query("DEFINE FIELD amount ON token_purchases TYPE number").await?;
        db.query("DEFINE FIELD timestamp ON token_purchases TYPE number").await?;
        db.query("DEFINE FIELD tx_digest ON token_purchases TYPE string").await?;

        db.query("DEFINE TABLE token_transfers SCHEMAFULL").await?;
        db.query("DEFINE FIELD from ON token_transfers TYPE string").await?;
        db.query("DEFINE FIELD to ON token_transfers TYPE string").await?;
        db.query("DEFINE FIELD amount ON token_transfers TYPE number").await?;
        db.query("DEFINE FIELD timestamp ON token_transfers TYPE number").await?;
        db.query("DEFINE FIELD tx_digest ON token_transfers TYPE string").await?;

        db.query("DEFINE TABLE price_updates SCHEMAFULL").await?;
        db.query("DEFINE FIELD new_price ON price_updates TYPE number").await?;
        db.query("DEFINE FIELD tokens_sold ON price_updates TYPE number").await?;
        db.query("DEFINE FIELD timestamp ON price_updates TYPE number").await?;
        db.query("DEFINE FIELD tx_digest ON price_updates TYPE string").await?;

        db.query("DEFINE TABLE liquidity_deployments SCHEMAFULL").await?;
        db.query("DEFINE FIELD launchpad_id ON liquidity_deployments TYPE string").await?;
        db.query("DEFINE FIELD sui_amount ON liquidity_deployments TYPE number").await?;
        db.query("DEFINE FIELD timestamp ON liquidity_deployments TYPE number").await?;
        db.query("DEFINE FIELD tx_digest ON liquidity_deployments TYPE string").await?;

        db.query("DEFINE TABLE pool_pauses SCHEMAFULL").await?;
        db.query("DEFINE FIELD launchpad_id ON pool_pauses TYPE string").await?;
        db.query("DEFINE FIELD timestamp ON pool_pauses TYPE number").await?;
        db.query("DEFINE FIELD tx_digest ON pool_pauses TYPE string").await?;

        db.query("DEFINE TABLE pool_unpauses SCHEMAFULL").await?;
        db.query("DEFINE FIELD launchpad_id ON pool_unpauses TYPE string").await?;
        db.query("DEFINE FIELD timestamp ON pool_unpauses TYPE number").await?;
        db.query("DEFINE FIELD tx_digest ON pool_unpauses TYPE string").await?;

        db.query("DEFINE TABLE launchpads SCHEMAFULL").await?;
        db.query("DEFINE FIELD launchpad_id ON launchpads TYPE string").await?;
        db.query("DEFINE FIELD creator ON launchpads TYPE string").await?;
        db.query("DEFINE FIELD name ON launchpads TYPE string").await?;
        db.query("DEFINE FIELD description ON launchpads TYPE string").await?;
        db.query("DEFINE FIELD token_supply ON launchpads TYPE number").await?;
        db.query("DEFINE FIELD initial_price ON launchpads TYPE number").await?;
        db.query("DEFINE FIELD price_increment ON launchpads TYPE number").await?;
        db.query("DEFINE FIELD website_url ON launchpads TYPE string").await?;
        db.query("DEFINE FIELD timestamp ON launchpads TYPE number").await?;
        db.query("DEFINE FIELD tx_digest ON launchpads TYPE string").await?;

        db.query("DEFINE TABLE vesting_claims SCHEMAFULL").await?;
        db.query("DEFINE FIELD user ON vesting_claims TYPE string").await?;
        db.query("DEFINE FIELD amount ON vesting_claims TYPE number").await?;
        db.query("DEFINE FIELD timestamp ON vesting_claims TYPE number").await?;
        db.query("DEFINE FIELD tx_digest ON vesting_claims TYPE string").await?;

        db.query("DEFINE TABLE fee_updates SCHEMAFULL").await?;
        db.query("DEFINE FIELD previous_fee ON fee_updates TYPE number").await?;
        db.query("DEFINE FIELD new_fee ON fee_updates TYPE number").await?;
        db.query("DEFINE FIELD tx_digest ON fee_updates TYPE string").await?;

        db.query("DEFINE TABLE admin_transfers SCHEMAFULL").await?;
        db.query("DEFINE FIELD previous_admin ON admin_transfers TYPE string").await?;
        db.query("DEFINE FIELD new_admin ON admin_transfers TYPE string").await?;
        db.query("DEFINE FIELD tx_digest ON admin_transfers TYPE string").await?;

        db.query("DEFINE TABLE balance_updates SCHEMAFULL").await?;
        db.query("DEFINE FIELD launchpad_id ON balance_updates TYPE string").await?;
        db.query("DEFINE FIELD holder ON balance_updates TYPE string").await?;
        db.query("DEFINE FIELD balance ON balance_updates TYPE number").await?;
        db.query("DEFINE FIELD timestamp ON balance_updates TYPE number").await?;
        db.query("DEFINE FIELD tx_digest ON balance_updates TYPE string").await?;

        Ok(Self {
            package_id: ObjectID::from_hex_literal(package_id)?,
            db,
        })
    }

    async fn handle_event(&mut self, event: SuiEvent) -> Result<()> {
        let timestamp = event.timestamp_ms;
        let tx_digest = event.id.tx_digest.to_string();
        let package_id = self.package_id.to_string();

        match event.type_.to_string().as_str() {
            event_type if event_type == format!("{}::launchpad::TokensPurchased", package_id) => {
                let purchase: TokensPurchased = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<TokensPurchased> = self.db
                    .query("CREATE token_purchases SET buyer = $buyer, amount = $amount, timestamp = $timestamp, tx_digest = $tx_digest")
                    .bind(("buyer", purchase.buyer))
                    .bind(("amount", purchase.amount))
                    .bind(("timestamp", timestamp))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            event_type if event_type == format!("{}::launchpad::TokensTransferred", package_id) => {
                let transfer: TokensTransferred = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<TokensTransferred> = self.db
                    .query("CREATE token_transfers SET from = $from, to = $to, amount = $amount, timestamp = $timestamp, tx_digest = $tx_digest")
                    .bind(("from", transfer.from))
                    .bind(("to", transfer.to))
                    .bind(("amount", transfer.amount))
                    .bind(("timestamp", timestamp))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            event_type if event_type == format!("{}::launchpad::PriceUpdate", package_id) => {
                let update: PriceUpdate = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<PriceUpdate> = self.db
                    .query("CREATE price_updates SET new_price = $new_price, tokens_sold = $tokens_sold, timestamp = $timestamp, tx_digest = $tx_digest")
                    .bind(("new_price", update.new_price))
                    .bind(("tokens_sold", update.tokens_sold))
                    .bind(("timestamp", timestamp))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            event_type if event_type == format!("{}::launchpad::LiquidityDeployed", package_id) => {
                let deploy: LiquidityDeployed = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<LiquidityDeployed> = self.db
                    .query("CREATE liquidity_deployments SET launchpad_id = $launchpad_id, sui_amount = $sui_amount, timestamp = $timestamp, tx_digest = $tx_digest")
                    .bind(("launchpad_id", deploy.launchpad_id))
                    .bind(("sui_amount", deploy.sui_amount))
                    .bind(("timestamp", timestamp))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            event_type if event_type == format!("{}::launchpad::PoolPaused", package_id) => {
                let pause: PoolPaused = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<PoolPaused> = self.db
                    .query("CREATE pool_pauses SET launchpad_id = $launchpad_id, timestamp = $timestamp, tx_digest = $tx_digest")
                    .bind(("launchpad_id", pause.launchpad_id))
                    .bind(("timestamp", timestamp))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            event_type if event_type == format!("{}::launchpad::PoolUnpaused", package_id) => {
                let unpause: PoolUnpaused = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<PoolUnpaused> = self.db
                    .query("CREATE pool_unpauses SET launchpad_id = $launchpad_id, timestamp = $timestamp, tx_digest = $tx_digest")
                    .bind(("launchpad_id", unpause.launchpad_id))
                    .bind(("timestamp", timestamp))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            event_type if event_type == format!("{}::launchpad::LaunchpadCreated", package_id) => {
                let launchpad: LaunchpadCreated = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<LaunchpadCreated> = self.db
                    .query("CREATE launchpads SET launchpad_id = $launchpad_id, creator = $creator, name = $name, description = $description, token_supply = $token_supply, initial_price = $initial_price, price_increment = $price_increment, website_url = $website_url, timestamp = $timestamp, tx_digest = $tx_digest")
                    .bind(("launchpad_id", launchpad.launchpad_id))
                    .bind(("creator", launchpad.creator))
                    .bind(("name", launchpad.name))
                    .bind(("description", launchpad.description))
                    .bind(("token_supply", launchpad.token_supply))
                    .bind(("initial_price", launchpad.initial_price))
                    .bind(("price_increment", launchpad.price_increment))
                    .bind(("website_url", launchpad.website_url))
                    .bind(("timestamp", timestamp))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            event_type if event_type == format!("{}::launchpad::VestingClaimed", package_id) => {
                let claim: VestingClaimed = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<VestingClaimed> = self.db
                    .query("CREATE vesting_claims SET user = $user, amount = $amount, timestamp = $timestamp, tx_digest = $tx_digest")
                    .bind(("user", claim.user))
                    .bind(("amount", claim.amount))
                    .bind(("timestamp", timestamp))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            event_type if event_type == format!("{}::launchpad::FeeUpdated", package_id) => {
                let fee: FeeUpdated = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<FeeUpdated> = self.db
                    .query("CREATE fee_updates SET previous_fee = $previous_fee, new_fee = $new_fee, tx_digest = $tx_digest")
                    .bind(("previous_fee", fee.previous_fee))
                    .bind(("new_fee", fee.new_fee))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            event_type if event_type == format!("{}::launchpad::AdminTransferred", package_id) => {
                let transfer: AdminTransferred = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<AdminTransferred> = self.db
                    .query("CREATE admin_transfers SET previous_admin = $previous_admin, new_admin = $new_admin, tx_digest = $tx_digest")
                    .bind(("previous_admin", transfer.previous_admin))
                    .bind(("new_admin", transfer.new_admin))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            event_type if event_type == format!("{}::launchpad::BalanceUpdate", package_id) => {
                let update: BalanceUpdate = bcs::from_bytes(&event.bcs)?;
                let _created: Vec<BalanceUpdate> = self.db
                    .query("CREATE balance_updates SET launchpad_id = $launchpad_id, holder = $holder, balance = $balance, timestamp = $timestamp, tx_digest = $tx_digest")
                    .bind(("launchpad_id", update.launchpad_id))
                    .bind(("holder", update.holder))
                    .bind(("balance", update.balance))
                    .bind(("timestamp", timestamp))
                    .bind(("tx_digest", tx_digest))
                    .await?
                    .take(0)?;
            }
            _ => {
                error!("Unknown event type: {}", event.type_);
            }
        }
        Ok(())
    }

    async fn start(&mut self) -> Result<()> {
        let rpc_url = env::var("SUI_RPC_URL").expect("SUI_RPC_URL must be set");
        info!("Starting indexer with RPC URL: {}", rpc_url);

        // Build client with both HTTP and WebSocket URLs
        let sui_client = if rpc_url.starts_with("https://") {
            let ws_url = rpc_url.replace("https://", "wss://");
            info!("Using WebSocket URL: {}", ws_url);
            SuiClientBuilder::default()
                .ws_url(&ws_url)
                .build(&rpc_url)
                .await?
        } else {
            // Fallback to HTTP-only client
            info!("Using HTTP-only client");
            SuiClientBuilder::default()
                .build(&rpc_url)
                .await?
        };

        info!("Successfully connected to Sui client");

        // Try WebSocket subscription first
        match sui_client
            .event_api()
            .subscribe_event(EventFilter::MoveModule {
                package: self.package_id,
                module: "launchpad".parse()?,
            })
            .await
        {
            Ok(mut subscribe_all) => {
                info!("Successfully subscribed to events via WebSocket");
                while let Some(event) = subscribe_all.next().await {
                    match event {
                        Ok(event) => {
                            if let Err(e) = self.handle_event(event).await {
                                error!("Failed to handle event: {}", e);
                            }
                        }
                        Err(e) => {
                            error!("Error receiving event: {}", e);
                            break; // Exit WebSocket loop on error
                        }
                    }
                }
            }
            Err(e) => {
                error!("Failed to subscribe via WebSocket: {}. Falling back to polling.", e);
                // Fallback to polling
                let mut cursor = None;
                loop {
                    // Query events using regular HTTP API
                    match sui_client
                        .event_api()
                        .query_events(EventFilter::MoveModule {
                            package: self.package_id,
                            module: "launchpad".parse()?,
                        }, cursor, None, false)
                        .await
                    {
                        Ok(event_page) => {
                            for event in event_page.data {
                                if let Err(e) = self.handle_event(event).await {
                                    error!("Failed to handle event: {}", e);
                                }
                            }
                            cursor = event_page.next_cursor;
                        }
                        Err(e) => {
                            error!("Failed to poll events: {}", e);
                        }
                    }

                    // Sleep before next poll
                    let poll_interval = env::var("POLL_INTERVAL_MS")
                        .ok()
                        .and_then(|s| s.parse().ok())
                        .unwrap_or(1000);
                    tokio::time::sleep(std::time::Duration::from_millis(poll_interval)).await;
                }
            }
        }

        Ok(())
    }

    // Helper functions to query the database
    async fn get_holder_balance(&self, wallet_address: &str) -> Result<Option<u64>> {
        let holder: Option<Holder> = self.db
            .select(("holders", wallet_address))
            .await?;
        Ok(holder.map(|h| h.balance))
    }

    async fn get_transactions(&self, wallet_address: &str) -> Result<Vec<Transaction>> {
        let transactions: Vec<Transaction> = self.db
            .query("SELECT transaction_type, timestamp, tx_digest FROM transactions WHERE wallet_address = $address ORDER BY timestamp DESC")
            .bind(("address", wallet_address.to_string()))
            .await?
            .take(0)?;
        Ok(transactions)
    }
}

fn setup_logging() -> Result<()> {
    let appender = FileAppender::builder()
        .build("indexer.log")?;

    let config = Config::builder()
        .appender(Appender::builder().build("file", Box::new(appender)))
        .logger(Logger::builder()
            .appender("file")
            .additive(false)
            .build("indexer_new", LevelFilter::Info))
        .logger(Logger::builder()
            .appender("file")
            .additive(false)
            .build("tokio_tungstenite", LevelFilter::Warn))
        .logger(Logger::builder()
            .appender("file")
            .additive(false)
            .build("tungstenite", LevelFilter::Warn))
        .logger(Logger::builder()
            .appender("file")
            .additive(false)
            .build("hyper", LevelFilter::Warn))
        .build(LogRoot::builder().appender("file").build(LevelFilter::Info))?;

    log4rs::init_config(config)?;
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenv().ok();
    setup_logging()?;

    let package_id = env::var("PACKAGE_ID").expect("PACKAGE_ID must be set");
    let mut indexer = Indexer::new(&package_id).await?;
    
    // Start indexing
    indexer.start().await?;
    Ok(())
}
