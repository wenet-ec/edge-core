// edge_metrics_collector/internal/vpn/manager.go
package vpn

import (
	"context"
	"fmt"
	"sync"
	"time"

	"edge_metrics_collector/internal/config"
)

type Manager struct {
	config     config.VPNConfig
	client     *TailscaleClient
	connection *Connection
	mu         sync.RWMutex
}

type Connection struct {
	Status           string    `json:"status"`
	VPNIp            string    `json:"vpn_ip,omitempty"`
	VPNHostname      string    `json:"vpn_hostname,omitempty"`
	ConnectedAt      time.Time `json:"connected_at,omitempty"`
	LastCheckedAt    time.Time `json:"last_checked_at"`
	LastError        string    `json:"last_error,omitempty"`
	LastErrorAt      time.Time `json:"last_error_at,omitempty"`
	ManualDisconnect bool      `json:"manual_disconnect"`
}

func NewManager(cfg config.VPNConfig) *Manager {
	return &Manager{
		config: cfg,
		client: NewTailscaleClient(cfg),
		connection: &Connection{
			Status:        "disconnected",
			LastCheckedAt: time.Now(),
		},
	}
}

func (m *Manager) Start(ctx context.Context) {

	// Initial connection attempt
	go m.initialConnect()

	// Start connectivity checker
	go m.connectivityChecker(ctx)

	// Start auto-reconnector
	go m.autoReconnector(ctx)
}

func (m *Manager) initialConnect() {
	if err := m.Connect(); err != nil {
	}
}

func (m *Manager) connectivityChecker(ctx context.Context) {
	ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			m.checkConnectivity()
		}
	}
}

func (m *Manager) autoReconnector(ctx context.Context) {
	ticker := time.NewTicker(time.Duration(m.config.ReconnectDelay) * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			m.attemptAutoReconnect()
		}
	}
}

func (m *Manager) Connect() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.connection.Status = "connecting"
	m.connection.LastCheckedAt = time.Now()
	m.connection.ManualDisconnect = false

	if err := m.client.Connect(); err != nil {
		m.connection.Status = "disconnected"
		m.connection.LastError = err.Error()
		m.connection.LastErrorAt = time.Now()
		return fmt.Errorf("connection failed: %w", err)
	}

	// Get connection info
	status, err := m.client.GetStatus()
	if err != nil {
		m.connection.Status = "connected"
		m.connection.ConnectedAt = time.Now()
		m.connection.LastError = ""
		return nil
	}

	m.connection.Status = "connected"
	m.connection.VPNIp = status.VPNIp
	m.connection.VPNHostname = status.VPNHostname
	m.connection.ConnectedAt = time.Now()
	m.connection.LastError = ""

	return nil
}

func (m *Manager) Disconnect() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if err := m.client.Disconnect(); err != nil {
		return fmt.Errorf("disconnection failed: %w", err)
	}

	m.connection.Status = "disconnected"
	m.connection.VPNIp = ""
	m.connection.VPNHostname = ""
	m.connection.ManualDisconnect = true
	m.connection.LastCheckedAt = time.Now()
	m.connection.LastError = ""

	return nil
}

func (m *Manager) GetStatus() *Connection {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Create a copy to avoid race conditions
	conn := *m.connection
	return &conn
}

func (m *Manager) checkConnectivity() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.connection.Status != "connected" {
		return
	}

	status, err := m.client.GetStatus()
	if err != nil {
		m.connection.Status = "disconnected"
		m.connection.VPNIp = ""
		m.connection.VPNHostname = ""
		m.connection.LastError = err.Error()
		m.connection.LastErrorAt = time.Now()
	} else {
		m.connection.VPNIp = status.VPNIp
		m.connection.VPNHostname = status.VPNHostname
		m.connection.LastError = ""
	}

	m.connection.LastCheckedAt = time.Now()
}

func (m *Manager) attemptAutoReconnect() {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Only reconnect if disconnected and not manually disconnected
	if m.connection.Status != "disconnected" || m.connection.ManualDisconnect {
		return
	}

	m.connection.Status = "connecting"
	m.connection.LastCheckedAt = time.Now()

	if err := m.client.Connect(); err != nil {
		m.connection.Status = "disconnected"
		m.connection.LastError = err.Error()
		m.connection.LastErrorAt = time.Now()
		return
	}

	// Get connection info
	status, err := m.client.GetStatus()
	if err != nil {
		m.connection.Status = "connected"
		m.connection.ConnectedAt = time.Now()
		m.connection.LastError = ""
		return
	}

	m.connection.Status = "connected"
	m.connection.VPNIp = status.VPNIp
	m.connection.VPNHostname = status.VPNHostname
	m.connection.ConnectedAt = time.Now()
	m.connection.LastError = ""

}
