// Copyright 2022 Patu
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

use std::{
    env, fs,
    io::{self, BufReader},
    path::PathBuf,
};

use clap::{Args, CommandFactory, ErrorKind, Parser, Subcommand};
use log::{debug, error};
use patu::{cni::NetworkConfig, ErrorCode};
use simplelog::{ColorChoice, ConfigBuilder, LevelFilter, TermLogger, TerminalMode};
use thiserror::Error;

#[derive(Parser)]
#[clap(author, version, about, long_about = None)]
struct Cli {
    #[clap(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    Add(AddArgs),
    Del(AddArgs),
}

#[derive(Args)]
struct AddArgs {
    #[clap(long, short, action)]
    netns_path: String,
    #[clap(long, short, action)]
    container_id: String,
    #[clap(long, short, action)]
    interface: String,
    #[clap(value_parser)]
    input: Option<PathBuf>,
}

#[derive(Error, Debug)]
pub enum Error {
    #[error("path to cgroup is not valid")]
    InvalidCgroup(#[from] io::Error),
    #[error("invalid network config")]
    InvalidNetworkConfig,
}

fn main() -> Result<(), anyhow::Error> {
    let cli = Cli::parse();

    TermLogger::init(
        LevelFilter::Debug,
        ConfigBuilder::new()
            .set_target_level(LevelFilter::Error)
            .set_location_level(LevelFilter::Error)
            .build(),
        TerminalMode::Mixed,
        ColorChoice::Auto,
    )?;

    match &cli.command {
        Some(Commands::Add(a)) => call_cni("ADD", a),
        Some(Commands::Del(a)) => call_cni("DEL", a),
        None => match env::var("CNI_COMMAND") {
            Ok(_) => {
                debug!("Executed as a CNI Plugin");
                if atty::is(atty::Stream::Stdin) {
                    let err = patu::cni::Error::new(
                        ErrorCode::IoFailure,
                        "Unable to read from stdin".to_string(),
                        None,
                    );
                    error!("No data on stdin");
                    eprintln!("{}", serde_json::to_string(&err).unwrap());
                    std::process::exit(1);
                }
                let res = serde_json::from_reader(io::stdin().lock()).map_err(|e| {
                    patu::cni::Error::new(
                        ErrorCode::InvalidNetworkConfig,
                        "Invalid Network Config".to_string(),
                        Some(e.to_string()),
                    )
                });
                let config = match res {
                    Ok(config) => config,
                    Err(e) => {
                        error!("failed to parse network config");
                        eprintln!("{}", serde_json::to_string(&e).unwrap());
                        std::process::exit(1);
                    }
                };
                match patu::cni(&config) {
                    Ok(res) => println!("{}", serde_json::to_string(&res).unwrap()),
                    Err(e) => eprintln!("{}", serde_json::to_string(&e).unwrap()),
                }
                Ok(())
            }
            Err(_) => {
                let mut cmd = Cli::command();
                cmd.error(
                    ErrorKind::DisplayHelpOnMissingArgumentOrSubcommand,
                    "Subcommand required when not being run as a CNI plugin",
                )
                .exit();
            }
        },
    }
}

fn call_cni(cni_comand: &'static str, a: &AddArgs) -> Result<(), anyhow::Error> {
    env::set_var("CNI_COMMAND", cni_comand);
    env::set_var("CNI_CONTAINERID", &a.container_id);
    env::set_var("CNI_NETNS", &a.netns_path);
    env::set_var("CNI_IFNAME", &a.interface);
    env::set_var("CNI_PATH", "/opt/cni/bin");
    let config: NetworkConfig = if let Some(input) = &a.input {
        let f = fs::File::open(input).unwrap();
        let reader = BufReader::new(f);
        let res = serde_json::from_reader(reader).map_err(|e| {
            patu::cni::Error::new(
                ErrorCode::InvalidNetworkConfig,
                "Invalid Network Config".to_string(),
                Some(e.to_string()),
            )
        });
        match res {
            Ok(config) => config,
            Err(e) => {
                eprintln!("{}", serde_json::to_string(&e).unwrap());
                std::process::exit(1);
            }
        }
    } else {
        if atty::is(atty::Stream::Stdin) {
            let err = patu::cni::Error::new(
                ErrorCode::IoFailure,
                "Unable to read from stdin".to_string(),
                None,
            );
            eprintln!("{}", serde_json::to_string(&err).unwrap());
            std::process::exit(1);
        }
        let res = serde_json::from_reader(io::stdin().lock()).map_err(|e| {
            patu::cni::Error::new(
                ErrorCode::InvalidNetworkConfig,
                "Invalid Network Config".to_string(),
                Some(e.to_string()),
            )
        });
        match res {
            Ok(config) => config,
            Err(e) => {
                eprintln!("{}", serde_json::to_string(&e).unwrap());
                std::process::exit(1);
            }
        }
    };
    match patu::cni(&config) {
        Ok(res) => {
            if !res.is_null() {
                println!("{}", serde_json::to_string(&res).unwrap())
            }
        }
        Err(e) => eprintln!("{}", serde_json::to_string(&e).unwrap()),
    }
    Ok(())
}
