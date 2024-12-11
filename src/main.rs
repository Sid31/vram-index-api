use anyhow::Result;
use chrono::{DateTime, Utc};
use dotenv::dotenv;
use move_core_types::identifier::Identifier;
use serde::{Deserialize, Serialize};
use std::{env, str::FromStr};
use sui_sdk::{
    rpc_types::{SuiEvent, EventFilter},
    types::base_types::ObjectID,
    SuiClientBuilder,
};
use surrealdb::{
    engine::local::{Db, Mem},
    sql::Thing,
    Surreal,
};

// Event structs
#[derive(Debug, Deserialize, Serialize)]
struct TokenPurchase {
    buyer: String,
    amount: u64,
}

#[derive(Debug, Deserialize, Serialize)]
struct TokenSale {
    seller: String,
    amount: u64,
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

// Database records
#[derive(Debug, Deserialize, Serialize)]
struct Transaction {
    id: Option<Thing>,
    wallet_address: String,
    transaction_type: String,
    amount: u64,
    timestamp: DateTime<Utc>,
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
    db: Surreal<Db>,
}

impl Indexer {
    async fn new(package_id: &str) -> Result<Self> {
        // Create in-memory database
        let db = Surreal::new::<Mem>(()).await?;
        db.use_ns("sui").use_db("indexer").await?;

        // Create tables and indexes
        db.query("DEFINE TABLE transactions SCHEMAFULL")
            .await?;
        db.query("DEFINE FIELD wallet_address ON transactions TYPE string")
            .await?;
        db.query("DEFINE FIELD transaction_type ON transactions TYPE string")
            .await?;
        db.query("DEFINE FIELD amount ON transactions TYPE number")
            .await?;
        db.query("DEFINE FIELD timestamp ON transactions TYPE datetime")
            .await?;
        db.query("DEFINE INDEX tx_wallet ON transactions FIELDS wallet_address")
            .await?;

        db.query("DEFINE TABLE holders SCHEMAFULL")
            .await?;
        db.query("DEFINE FIELD wallet_address ON holders TYPE string")
            .await?;
        db.query("DEFINE INDEX holder_wallet ON holders FIELDS wallet_address UNIQUE")
            .await?;
        db.query("DEFINE FIELD balance ON holders TYPE number")
            .await?;
        db.query("DEFINE FIELD last_updated ON holders TYPE datetime")
            .await?;

        Ok(Self {
            package_id: ObjectID::from_str(package_id)?,
            db,
        })
    }

    async fn handle_event(&self, event: SuiEvent) -> Result<()> {
        let timestamp = DateTime::<Utc>::from_timestamp_millis(
            event.timestamp_ms.ok_or_else(|| anyhow::anyhow!("Missing timestamp"))? as i64,
        )
        .ok_or_else(|| anyhow::anyhow!("Invalid timestamp"))?;

        let event_type = format!("{}::{}", event.type_.module, event.type_.name);

        if event_type.ends_with("::TokenPurchase") {
            if let Ok(purchase) = serde_json::from_value::<TokenPurchase>(event.parsed_json) {
                // Record purchase transaction
                let tx = Transaction {
                    id: None,
                    wallet_address: purchase.buyer.clone(),
                    transaction_type: "buy".to_string(),
                    amount: purchase.amount,
                    timestamp,
                };
                let _created: Vec<Transaction> = self.db
                    .create("transactions")
                    .content(tx)
                    .await?;

                // Update holder balance
                let existing: Option<Holder> = self.db
                    .select(("holders", &purchase.buyer))
                    .await?;

                let new_balance = existing
                    .map(|h| h.balance + purchase.amount)
                    .unwrap_or(purchase.amount);

                let holder = Holder {
                    id: None,
                    wallet_address: purchase.buyer.clone(),
                    balance: new_balance,
                    last_updated: timestamp,
                };
                
                let _: Vec<Holder> = self.db
                    .create("holders")
                    .content(holder)
                    .await?;
            }
        } else if event_type.ends_with("::TokenSale") {
            if let Ok(sale) = serde_json::from_value::<TokenSale>(event.parsed_json) {
                // Record sale transaction
                let tx = Transaction {
                    id: None,
                    wallet_address: sale.seller.clone(),
                    transaction_type: "sell".to_string(),
                    amount: sale.amount,
                    timestamp,
                };
                let _: Vec<Transaction> = self.db
                    .create("transactions")
                    .content(tx)
                    .await?;

                // Update holder balance
                if let Some(mut holder) = self.db
                    .select::<Option<Holder>>(("holders", &sale.seller))
                    .await?
                {
                    holder.balance = holder.balance.saturating_sub(sale.amount);
                    holder.last_updated = timestamp;
                    let _: Option<Holder> = self.db
                        .update(("holders", holder.wallet_address.clone()))
                        .content(holder)
                        .await?;
                }
            }
        } else if event_type.ends_with("::PoolPaused") {
            if let Ok(_pause_event) = serde_json::from_value::<PoolPaused>(event.parsed_json) {
                // Record pool pause event
                let tx = Transaction {
                    id: None,
                    wallet_address: "SYSTEM".to_string(),
                    transaction_type: "pool_paused".to_string(),
                    amount: 0,
                    timestamp,
                };
                let _created: Vec<Transaction> = self.db
                    .create("transactions")
                    .content(tx)
                    .await?;
            }
        } else if event_type.ends_with("::PoolUnpaused") {
            if let Ok(_unpause_event) = serde_json::from_value::<PoolUnpaused>(event.parsed_json) {
                // Record pool unpause event
                let tx = Transaction {
                    id: None,
                    wallet_address: "SYSTEM".to_string(),
                    transaction_type: "pool_unpaused".to_string(),
                    amount: 0,
                    timestamp,
                };
                let _created: Vec<Transaction> = self.db
                    .create("transactions")
                    .content(tx)
                    .await?;
            }
        }

        Ok(())
    }

    async fn start(&self) -> Result<()> {
        println!("Starting indexer for package: {}", self.package_id);

        let sui = SuiClientBuilder::default()
            .build(env::var("SUI_RPC_URL")?)
            .await?;

        let filter = EventFilter::MoveModule {
            package: self.package_id,
            module: Identifier::new("launchpad")?,
        };

        let poll_interval = env::var("POLL_INTERVAL_MS")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(1000);

        println!("Successfully initialized. Polling for events every {} ms", poll_interval);
        
        let mut cursor = None;
        
        loop {
            match sui.event_api().query_events(filter.clone(), cursor, Some(50), false).await {
                Ok(page) => {
                    for event in page.data {
                        if let Err(e) = self.handle_event(event).await {
                            eprintln!("Error handling event: {}", e);
                        }
                    }
                    
                    cursor = page.next_cursor;
                }
                Err(e) => {
                    eprintln!("Error querying events: {}", e);
                }
            }
            
            tokio::time::sleep(tokio::time::Duration::from_millis(poll_interval)).await;
        }
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
            .query("SELECT * FROM transactions WHERE wallet_address = $address ORDER BY timestamp DESC")
            .bind(("address", wallet_address))
            .await?
            .take(0)?;
        Ok(transactions)
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenv().ok();

    println!("Starting indexer...");
    let indexer = Indexer::new(&env::var("PACKAGE_ID")?).await?;
    indexer.start().await?;

    Ok(())
}
