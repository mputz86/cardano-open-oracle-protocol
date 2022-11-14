# shellcheck disable=SC2085,SC2155,SC2002,SC2003,SC2086
JS_STORE_DIR=.json-fs-store
COOP_PAB_DIR=.coop-pab-cli
COOP_PUBLISHER_DIR=.coop-publisher-cli
CLUSTER_DIR=.local-cluster # As specified in resources/pabConfig.yaml

WALLETS=.wallets

RESOURCES=resources

function clean {
    rm -fR $JS_STORE_DIR
    rm -fR $COOP_PAB_DIR
    rm -fR $COOP_PUBLISHER_DIR
    rm -fR $CLUSTER_DIR
    rm -fR $WALLETS
}

function make-dirs {
    mkdir $JS_STORE_DIR
    mkdir $COOP_PAB_DIR
    mkdir $COOP_PUBLISHER_DIR
    mkdir $CLUSTER_DIR
    mkdir $CLUSTER_DIR/scripts
    mkdir $CLUSTER_DIR/txs
    mkdir $WALLETS
}

# Generate TLS keys for Publisher, FactStatementStore and TxBuilder services
function generate-keys {
    openssl genrsa -out $1/key.pem 2048
    openssl req -new -key $1/key.pem -out $1/certificate.csr -subj "/C=US/ST=st/L=l/O=o/OU=IT/CN=localhost"
    openssl x509 -req -in $1/certificate.csr -signkey $1/key.pem -out $1/certificate.pem -extfile $RESOURCES/ssl-extensions-x509.conf -extensions v3_ca -subj "/C=US/ST=st/L=l/O=o/OU=IT/CN=localhost"
    openssl x509 -text -in $1/certificate.pem
}

# Prelude FactStatementStore
function prelude-js-fs-store {
    sqlite3 -batch $JS_STORE_DIR/json-store.db ""
    json-fs-store-cli genesis --db $JS_STORE_DIR/json-store.db
    json-fs-store-cli insert-fact-statement --db $JS_STORE_DIR/json-store.db --fact_statement_id "someidA" --json "[1,2,3]"
    json-fs-store-cli insert-fact-statement --db $JS_STORE_DIR/json-store.db --fact_statement_id "someidB" --json "[4,5,6]"
    json-fs-store-cli insert-fact-statement --db $JS_STORE_DIR/json-store.db --fact_statement_id "someidC" --json "[7,8,9]"
	  echo "SELECT * FROM fact_statements" | sqlite3 $JS_STORE_DIR/json-store.db
}

# Run the FactStatementStore generic Json implementation
function run-js-fs-store {
    json-fs-store-cli fact-statement-store-grpc --db $JS_STORE_DIR/json-store.db
}

# Run the Plutip Local Cluster (cardano-node and wallet creation)
function run-cluster {
    local-cluster --wallet-dir $WALLETS -n 10 --utxos 5 --chain-index-port 9084 --slot-len 1s --epoch-size 100000
}

# Run manually to parse the config outputted by run-cluster
function parse-cluster-config {
    cat > $COOP_PAB_DIR/plutip-cluster-config
    make-exports
    # So BPI doesn't have access to it
    mv $WALLETS/signing-key-$SUBMITTER_PKH.skey $WALLETS/my-key-$SUBMITTER_PKH.skey
}

function make-exports {
    export GOD_PKH=$(cat $COOP_PAB_DIR/plutip-cluster-config | grep -E "Wallet 1 PKH" | cut -d ":" -f 2 | xargs)
    export AA_PKH=$(cat $COOP_PAB_DIR/plutip-cluster-config | grep -E "Wallet 2 PKH" | cut -d ":" -f 2 | xargs)
    export AUTH_PKH=$(cat $COOP_PAB_DIR/plutip-cluster-config | grep -E "Wallet 3 PKH" | cut -d ":" -f 2 | xargs)
    export CERT_RDMR_PKH=$(cat $COOP_PAB_DIR/plutip-cluster-config | grep -E "Wallet 4 PKH" | cut -d ":" -f 2 | xargs)
    export FEE_PKH=$(cat $COOP_PAB_DIR/plutip-cluster-config | grep -E "Wallet 5 PKH" | cut -d ":" -f 2 | xargs)
    export SUBMITTER_PKH=$(cat $COOP_PAB_DIR/plutip-cluster-config | grep -E "Wallet 6 PKH" | cut -d ":" -f 2 | xargs)
    export CARDANO_NODE_SOCKET_PATH=$(cat $COOP_PAB_DIR/plutip-cluster-config | grep CardanoNodeConn | grep -E -o '"[^"]+"' | sed s/\"//g)
}

function show-env {
    export | grep -E "WALLET|CARDANO_NODE_SOCKET_PATH"
}

function coop-genesis {
    make-exports
    coop-pab-cli deploy --god-wallet $GOD_PKH --aa-wallet $AA_PKH
}

function coop-mint-cert-redeemers {
    make-exports
    coop-pab-cli mint-cert-redeemers --cert-rdmr-wallet $CERT_RDMR_PKH --cert-rdmrs-to-mint 100
}

function coop-mint-authentication {
    make-exports
    NOW=$(get-onchain-time) && coop-pab-cli mint-auth --aa-wallet $AA_PKH --certificate-valid-from $NOW --certificate-valid-to "$(expr $NOW + 60 \* 60 \* 1000)" --auth-wallet $AUTH_PKH
}

function coop-redist-auth {
    make-exports
    coop-pab-cli redistribute-auth --auth-wallet $AUTH_PKH
}

function coop-run-tx-builder-grpc {
    make-exports
    coop-pab-cli tx-builder-grpc --auth-wallet $AUTH_PKH --fee-wallet $FEE_PKH
}

function coop-garbage-collect {
    make-exports
    coop-pab-cli garbage-collect --cert-rdmr-wallet $CERT_RDMR_PKH
}

function coop-get-state {
    make-exports
    coop-pab-cli get-state --any-wallet ${GOD_PKH}
    cat $COOP_PAB_DIR/coop-state.json | json_pp
}

function coop-poll-state {
    make-exports
    while true; do
        clear;
        coop-get-state;
        sleep 5;
    done;
}

function get-onchain-time {
    make-exports
    coop-pab-cli get-state --any-wallet ${GOD_PKH} | grep "Current node client time range" | grep POSIXTime | grep -E -o "[0-9]+"
}

function run-grpcui {
    make-exports
    grpcui -insecure -import-path $RESOURCES/coop-proto -proto $RESOURCES/coop-proto/tx-builder-service.proto localhost:5081
}

function coop-mint-fs {
    make-exports
    resp=$(grpcurl -insecure -import-path $RESOURCES/coop-proto -proto $RESOURCES/coop-proto/tx-builder-service.proto -d @ localhost:5081 coop.tx_builder.TxBuilder/createMintFsTx <<EOF
{
  "factStatements": [
    {
      "fsId": "$(echo -ne 'the best id1' | base64)",
      "gcAfter": {
        "extended": "NEG_INF"
      },
      "fs": {
        "pdint": "1337"
      }
    },
    {
      "fsId": "$(echo -ne 'the best id2' | base64)",
      "gcAfter": {
        "extended": "NEG_INF"
      },
      "fs": {
        "pdbytes": "$(echo -ne 'some bytes' | base64)"
      }
    },
    {
      "fsId": "$(echo -ne 'the best id3' | base64)",
      "gcAfter": {
        "extended": "NEG_INF"
      },
      "fs": {
        "pdlist": {
          "elements": [
            {
              "pdint": "1337"
            }
          ]
        }
      }
    },
    {
      "fsId": "$(echo -ne 'the best id4' | base64)",
      "gcAfter": {
        "extended": "FINITE",
        "finiteLedgerTime": "$(expr "$(get-onchain-time)" + 60 \* 60 \* 1000)"
      },
      "fs": {
        "pdlist": {
          "elements": [
            {
              "pdint": "1337"
            }
          ]
        }
      }
    },
    {
      "fsId": "$(echo -ne 'the best id5' | base64)",
      "gcAfter": {
        "extended": "FINITE",
        "finiteLedgerTime": "$(expr "$(get-onchain-time)" + 60 \* 60 \* 1000)"
      },
      "fs": {
        "pdlist": {
          "elements": [
            {
              "pdint": "1337"
            }
          ]
        }
      }
    }
  ],
  "submitter": {
    "base16": "$SUBMITTER_PKH"
  }
}
EOF
           )
    rawTx=$(echo $resp | jq '.success.mintFsTx | .cborHex = .cborBase16 | del(.cborBase16) | .description = "" | .type = "Tx BabbageEra"')
    echo $resp | jq '.info'
    echo $resp | jq '.error'
    echo $rawTx > $COOP_PAB_DIR/signed
}

function coop-gc-fs {
    make-exports
    resp=$(grpcurl -insecure -import-path ../coop-proto -proto ../coop-proto/tx-builder-service.proto -d @ localhost:5081 coop.tx_builder.TxBuilder/createGcFsTx <<EOF
    {
        "fsIds": ["eW==", "YXNkCg=="],
        "submitter": {
            "base16": "$SUBMITTER_PKH"
        }
    }

EOF
        )
    rawTx=$(echo $resp | jq '.success.gcFsTx | .cborHex = .cborBase16 | del(.cborBase16) | .description = "" | .type = "Tx BabbageEra"')
    echo $resp | jq '.info'
    echo $resp | jq '.error'
    echo $rawTx > $COOP_PAB_DIR/signed
}

function cardano-cli-sign {
    make-exports
    cardano-cli transaction sign --tx-file $COOP_PAB_DIR/signed --signing-key-file $WALLETS/no-plutip-signing-key-$SUBMITTER_PKH.skey --out-file $COOP_PAB_DIR/ready
}

function cardano-cli-submit {
    make-exports
    cardano-cli transaction submit --tx-file $COOP_PAB_DIR/ready  --mainnet
}

function coop-prelude {
    make-exports
    coop-genesis
    coop-mint-cert-redeemers
    coop-mint-authentication
    coop-redist-auth
    coop-run-tx-builder-grpc
}