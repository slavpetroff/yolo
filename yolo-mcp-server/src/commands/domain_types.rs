use std::fmt;

/// A validated task identifier (e.g., "1", "5").
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct TaskId(String);

impl TaskId {
    pub fn new(s: impl Into<String>) -> Self {
        Self(s.into())
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
    /// Parse as a 1-based task number.
    pub fn as_number(&self) -> Option<u32> {
        self.0.parse().ok()
    }
}

impl fmt::Display for TaskId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// A phase number (positive integer).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Phase(pub u32);

impl Phase {
    pub fn new(n: u32) -> Self {
        Self(n)
    }
    pub fn as_u32(&self) -> u32 {
        self.0
    }
}

impl fmt::Display for Phase {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// A wave number within a phase (1-based).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Wave(pub u32);

impl Wave {
    pub fn new(n: u32) -> Self {
        Self(n)
    }
}

impl fmt::Display for Wave {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// A lock resource identifier.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ResourceId(String);

impl ResourceId {
    pub fn new(s: impl Into<String>) -> Self {
        Self(s.into())
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for ResourceId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_task_id_as_number() {
        assert_eq!(TaskId::new("3").as_number(), Some(3));
        assert_eq!(TaskId::new("abc").as_number(), None);
    }

    #[test]
    fn test_task_id_display() {
        assert_eq!(format!("{}", TaskId::new("42")), "42");
    }

    #[test]
    fn test_phase_new() {
        assert_eq!(Phase::new(5).as_u32(), 5);
    }

    #[test]
    fn test_resource_id_as_str() {
        assert_eq!(ResourceId::new("src/main.rs").as_str(), "src/main.rs");
    }
}
