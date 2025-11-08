pub mod interfaces {
    pub mod IGateway;
}

pub mod contracts {
    pub mod Gateway;
    pub mod GatewaySettingManager;
}

#[cfg(test)]
pub mod mocks {
    pub mod MyToken;
}
