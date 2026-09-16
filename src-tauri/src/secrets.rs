pub struct SecretStore;
impl SecretStore {
    fn entry() -> Result<keyring::Entry, String> {
        keyring::Entry::new("com.linguaglass.desktop", "deepseek")
            .map_err(|_| "系统凭据存储不可用".into())
    }
    pub fn read() -> Result<Option<String>, String> {
        match Self::entry()?.get_password() {
            Ok(key) => Ok(Some(key)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(_) => Err("无法读取系统凭据，请解锁系统密钥环".into()),
        }
    }
    pub fn save(key: &str) -> Result<(), String> {
        if key.trim().is_empty() || key.len() > 512 || key.chars().any(char::is_whitespace) {
            return Err("请输入有效的 API Key".into());
        }
        Self::entry()?
            .set_password(key)
            .map_err(|_| "无法保存到系统凭据存储".into())
    }
    pub fn delete() -> Result<(), String> {
        match Self::entry()?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(_) => Err("无法删除系统凭据".into()),
        }
    }
}
