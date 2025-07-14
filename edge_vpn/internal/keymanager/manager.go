// edge_vpn/internal/keymanager/manager.go
package keymanager

import (
	"edge_vpn/internal/headscale"
	"fmt"
	"log"
	"sync"
	"time"
)

const (
	DefaultRotationIntervalDays = 30
	RotationWarningDays         = 7
)

// Manager handles API key lifecycle management
type Manager struct {
	storage         *Storage
	headscaleClient *headscale.Client
	currentKey      *APIKeyData
	mutex           sync.RWMutex
}

// NewManager creates a new key manager instance
func NewManager(keyFilePath string) *Manager {
	return &Manager{
		storage:         NewStorage(keyFilePath),
		headscaleClient: headscale.NewClient(),
	}
}

// Initialize sets up the key manager and ensures we have a valid API key
func (m *Manager) Initialize() error {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	log.Println("Initializing API key manager...")

	// Try to load existing key
	keyData, err := m.storage.Load()
	if err != nil {
		log.Printf("No existing key found or failed to load: %v", err)
		return m.generateNewKeyWithValidation()
	}

	// Validate existing key
	if keyData.IsExpired() {
		log.Println("Existing key is expired, generating new one...")
		return m.generateNewKeyWithValidation()
	}

	// Test the key with retry logic for startup
	log.Println("Validating existing API key...")
	if err := m.headscaleClient.ValidateAPIKeyWithRetry(keyData.CurrentKey, 30, 2*time.Second); err != nil {
		log.Printf("Existing key validation failed: %v", err)
		log.Println("Generating new key...")
		return m.generateNewKeyWithValidation()
	}

	log.Println("Using existing valid API key")
	m.currentKey = keyData

	if keyData.NeedsRotation() {
		log.Printf("Key will expire in less than %d days, scheduling rotation", RotationWarningDays)
	}

	return nil
}

// Update generateNewKey to use proper validation
func (m *Manager) generateNewKeyWithValidation() error {
	log.Println("Generating new API key...")

	apiKey, err := m.headscaleClient.CreateAPIKey(DefaultRotationIntervalDays)
	if err != nil {
		return fmt.Errorf("failed to create API key: %w", err)
	}

	// Validate the new key with retry logic (headscale might need time to process it)
	log.Println("Validating newly generated API key...")
	if err := m.headscaleClient.ValidateAPIKeyWithRetry(apiKey, 15, 1*time.Second); err != nil {
		return fmt.Errorf("newly generated key validation failed: %w", err)
	}

	now := time.Now()
	keyData := &APIKeyData{
		CurrentKey:           apiKey,
		CreatedAt:            now,
		ExpiresAt:            now.AddDate(0, 0, DefaultRotationIntervalDays),
		RotationIntervalDays: DefaultRotationIntervalDays,
	}

	if err := m.storage.Save(keyData); err != nil {
		return fmt.Errorf("failed to save new key: %w", err)
	}

	m.currentKey = keyData
	log.Printf("Successfully generated, validated, and saved new API key (expires: %s)", keyData.ExpiresAt.Format(time.RFC3339))

	return nil
}

// GetCurrentKey returns the current valid API key (thread-safe)
func (m *Manager) GetCurrentKey() (string, error) {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	if m.currentKey == nil {
		return "", fmt.Errorf("no API key available")
	}

	if m.currentKey.IsExpired() {
		return "", fmt.Errorf("current API key is expired")
	}

	return m.currentKey.CurrentKey, nil
}

// RotateKey generates a new API key and replaces the current one
func (m *Manager) RotateKey() error {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	log.Println("Starting API key rotation...")

	oldKey := m.currentKey

	// Generate new key
	if err := m.generateNewKey(); err != nil {
		return fmt.Errorf("failed to generate new key during rotation: %w", err)
	}

	// Expire the old key if we have one
	if oldKey != nil {
		keyPrefix := m.headscaleClient.GetKeyPrefix(oldKey.CurrentKey)
		if err := m.headscaleClient.ExpireAPIKey(keyPrefix); err != nil {
			log.Printf("Warning: failed to expire old API key %s: %v", keyPrefix, err)
			// Don't fail the rotation, just log the warning
		} else {
			log.Printf("Successfully expired old API key %s", keyPrefix)
		}
	}

	log.Println("API key rotation completed successfully")
	return nil
}

// CheckRotationNeeded returns true if the key needs rotation
func (m *Manager) CheckRotationNeeded() bool {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	if m.currentKey == nil {
		return true
	}

	return m.currentKey.NeedsRotation()
}

// generateNewKey creates a new API key and saves it (must be called with mutex locked)
func (m *Manager) generateNewKey() error {
	return m.generateNewKeyWithValidation()
}

// GetKeyInfo returns information about the current key (for debugging/monitoring)
func (m *Manager) GetKeyInfo() map[string]interface{} {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	if m.currentKey == nil {
		return map[string]interface{}{
			"status": "no_key",
		}
	}

	return map[string]interface{}{
		"status":         "active",
		"created_at":     m.currentKey.CreatedAt.Format(time.RFC3339),
		"expires_at":     m.currentKey.ExpiresAt.Format(time.RFC3339),
		"needs_rotation": m.currentKey.NeedsRotation(),
		"is_expired":     m.currentKey.IsExpired(),
		"key_prefix":     m.headscaleClient.GetKeyPrefix(m.currentKey.CurrentKey),
	}
}
