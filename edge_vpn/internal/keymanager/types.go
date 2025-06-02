// edge_vpn/internal/keymanager/types.go
package keymanager

import (
	"encoding/json"
	"time"
)

// APIKeyData represents the stored API key information
type APIKeyData struct {
	CurrentKey           string    `json:"current_key"`
	CreatedAt            time.Time `json:"created_at"`
	ExpiresAt            time.Time `json:"expires_at"`
	RotationIntervalDays int       `json:"rotation_interval_days"`
}

// IsExpired checks if the key is expired or will expire soon
func (k *APIKeyData) IsExpired() bool {
	return time.Now().After(k.ExpiresAt)
}

// NeedsRotation checks if the key should be rotated (within 7 days of expiry)
func (k *APIKeyData) NeedsRotation() bool {
	warningPeriod := 7 * 24 * time.Hour
	return time.Now().Add(warningPeriod).After(k.ExpiresAt)
}

// ToJSON converts the key data to JSON bytes
func (k *APIKeyData) ToJSON() ([]byte, error) {
	return json.MarshalIndent(k, "", "  ")
}

// FromJSON parses JSON bytes into APIKeyData
func (k *APIKeyData) FromJSON(data []byte) error {
	return json.Unmarshal(data, k)
}
