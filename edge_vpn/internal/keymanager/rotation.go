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

	// Check for rotation every 6 hours
	_, err := r.cron.AddFunc("0 */6 * * *", r.checkAndRotate)
	if err != nil {
		return err
	}

	r.cron.Start()
	return nil
}

// Stop stops the background rotation service
func (r *RotationService) Stop() {
	r.cron.Stop()
}

// checkAndRotate checks if rotation is needed and performs it
func (r *RotationService) checkAndRotate() {

	if !r.manager.CheckRotationNeeded() {
		return
	}

	if err := r.manager.RotateKey(); err != nil {
		log.Printf("Key rotation failed: %v", err)
		return
	}

}

// ForceRotation manually triggers a key rotation
func (r *RotationService) ForceRotation() error {
	return r.manager.RotateKey()
}
