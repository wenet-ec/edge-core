// edge_vpn/internal/keymanager/rotation.go
package keymanager

import (
	"log"

	"github.com/robfig/cron/v3"
)

// RotationService handles background key rotation
type RotationService struct {
	manager *Manager
	cron    *cron.Cron
}

// NewRotationService creates a new rotation service
func NewRotationService(manager *Manager) *RotationService {
	return &RotationService{
		manager: manager,
		cron:    cron.New(),
	}
}

// Start begins the background rotation service
func (r *RotationService) Start() error {
	log.Println("Starting key rotation service...")

	// Check for rotation every 6 hours
	_, err := r.cron.AddFunc("0 */6 * * *", r.checkAndRotate)
	if err != nil {
		return err
	}

	r.cron.Start()
	log.Println("Key rotation service started (checking every 6 hours)")
	return nil
}

// Stop stops the background rotation service
func (r *RotationService) Stop() {
	log.Println("Stopping key rotation service...")
	r.cron.Stop()
}

// checkAndRotate checks if rotation is needed and performs it
func (r *RotationService) checkAndRotate() {
	log.Println("Checking if key rotation is needed...")

	if !r.manager.CheckRotationNeeded() {
		log.Println("Key rotation not needed")
		return
	}

	log.Println("Key rotation needed, starting rotation...")
	if err := r.manager.RotateKey(); err != nil {
		log.Printf("Key rotation failed: %v", err)
		return
	}

	log.Println("Key rotation completed successfully")
}

// ForceRotation manually triggers a key rotation
func (r *RotationService) ForceRotation() error {
	log.Println("Forcing key rotation...")
	return r.manager.RotateKey()
}
