// edge_vpn/internal/keymanager/storage.go
package keymanager

import (
	"fmt"
	"os"
	"path/filepath"
)

const (
	DefaultKeyFilePath = "/var/lib/headscale/api_key.json"
	BackupKeyFilePath  = "/var/lib/headscale/api_key.json.backup"
)

// Storage handles file-based persistence of API keys
type Storage struct {
	keyFilePath    string
	backupFilePath string
}

// NewStorage creates a new storage instance
func NewStorage(keyFilePath string) *Storage {
	if keyFilePath == "" {
		keyFilePath = DefaultKeyFilePath
	}

	return &Storage{
		keyFilePath:    keyFilePath,
		backupFilePath: keyFilePath + ".backup",
	}
}

// EnsureDirectory creates the directory if it doesn't exist
func (s *Storage) EnsureDirectory() error {
	dir := filepath.Dir(s.keyFilePath)
	return os.MkdirAll(dir, 0755)
}

// Load reads the API key data from file
func (s *Storage) Load() (*APIKeyData, error) {
	data, err := os.ReadFile(s.keyFilePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("key file not found: %w", err)
		}
		return nil, fmt.Errorf("failed to read key file: %w", err)
	}

	keyData := &APIKeyData{}
	if err := keyData.FromJSON(data); err != nil {
		return nil, fmt.Errorf("failed to parse key file: %w", err)
	}

	return keyData, nil
}

// Save writes the API key data to file with atomic operation
func (s *Storage) Save(keyData *APIKeyData) error {
	if err := s.EnsureDirectory(); err != nil {
		return fmt.Errorf("failed to ensure directory: %w", err)
	}

	// Create backup if original exists
	if _, err := os.Stat(s.keyFilePath); err == nil {
		if err := s.createBackup(); err != nil {
			return fmt.Errorf("failed to create backup: %w", err)
		}
	}

	// Write to temporary file first for atomic operation
	tempFile := s.keyFilePath + ".tmp"
	data, err := keyData.ToJSON()
	if err != nil {
		return fmt.Errorf("failed to serialize key data: %w", err)
	}

	if err := os.WriteFile(tempFile, data, 0600); err != nil {
		return fmt.Errorf("failed to write temp file: %w", err)
	}

	// Atomic rename
	if err := os.Rename(tempFile, s.keyFilePath); err != nil {
		os.Remove(tempFile) // Cleanup on failure
		return fmt.Errorf("failed to rename temp file: %w", err)
	}

	return nil
}

// createBackup creates a backup of the current key file
func (s *Storage) createBackup() error {
	return copyFile(s.keyFilePath, s.backupFilePath)
}

// RestoreFromBackup restores the key file from backup
func (s *Storage) RestoreFromBackup() error {
	if _, err := os.Stat(s.backupFilePath); os.IsNotExist(err) {
		return fmt.Errorf("backup file not found")
	}
	return copyFile(s.backupFilePath, s.keyFilePath)
}

// copyFile copies a file from src to dst
func copyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, 0600)
}
