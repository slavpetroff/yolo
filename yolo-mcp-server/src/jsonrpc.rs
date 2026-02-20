use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Request {
    pub jsonrpc: String,
    pub id: serde_json::Value,
    pub method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<serde_json::Value>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Notification {
    pub jsonrpc: String,
    pub method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<serde_json::Value>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct Response {
    pub jsonrpc: String,
    pub id: serde_json::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct JsonRpcError {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
}

#[derive(Deserialize, Debug)]
#[serde(untagged)]
pub enum IncomingMessage {
    Request(Request),
    Notification(Notification),
    Response(Response),
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_parse_request() {
        let req_str = r#"{"jsonrpc": "2.0", "id": 1, "method": "test"}"#;
        let msg: IncomingMessage = serde_json::from_str(req_str).unwrap();
        match msg {
            IncomingMessage::Request(req) => {
                assert_eq!(req.jsonrpc, "2.0");
                assert_eq!(req.id, json!(1));
                assert_eq!(req.method, "test");
                assert!(req.params.is_none());
            }
            _ => panic!("Expected Request"),
        }
    }

    #[test]
    fn test_parse_notification() {
        let notif_str = r#"{"jsonrpc": "2.0", "method": "update", "params": [1,2,3]}"#;
        let msg: IncomingMessage = serde_json::from_str(notif_str).unwrap();
        match msg {
            IncomingMessage::Notification(notif) => {
                assert_eq!(notif.jsonrpc, "2.0");
                assert_eq!(notif.method, "update");
                assert_eq!(notif.params, Some(json!([1,2,3])));
            }
            _ => panic!("Expected Notification"),
        }
    }
}
