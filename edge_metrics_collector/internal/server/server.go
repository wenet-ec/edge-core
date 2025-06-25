// edge_metrics_collector/internal/server/server.go
package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"edge_metrics_collector/internal/config"
	"edge_metrics_collector/internal/vpn"
)

type Server struct {
	config     config.ServerConfig
	vpnManager *vpn.Manager
	server     *http.Server
}

type HealthResponse struct {
	Status        string `json:"status"`
	Timestamp     string `json:"timestamp"`
	VPNConnected  bool   `json:"vpn_connected"`
	VMAgentStatus string `json:"vmagent_status"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

func New(cfg config.ServerConfig, vpnManager *vpn.Manager) *Server {
	s := &Server{
		config:     cfg,
		vpnManager: vpnManager,
	}

	mux := http.NewServeMux()
	s.setupRoutes(mux)

	s.server = &http.Server{
		Addr:    fmt.Sprintf(":%d", cfg.Port),
		Handler: mux,
	}

	return s
}

func (s *Server) setupRoutes(mux *http.ServeMux) {
	// Health endpoint
	mux.HandleFunc("/health", s.healthHandler)

	// VPN endpoints
	mux.HandleFunc("/vpn/status", s.vpnStatusHandler)
	mux.HandleFunc("/vpn/connect", s.vpnConnectHandler)
	mux.HandleFunc("/vpn/disconnect", s.vpnDisconnectHandler)
}

func (s *Server) ListenAndServe() error {
	return s.server.ListenAndServe()
}

func (s *Server) Shutdown(ctx context.Context) error {
	return s.server.Shutdown(ctx)
}

func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	vpnStatus := s.vpnManager.GetStatus()

	response := HealthResponse{
		Status:        "ok",
		Timestamp:     time.Now().UTC().Format(time.RFC3339),
		VPNConnected:  vpnStatus.Status == "connected",
		VMAgentStatus: "not_implemented", // TODO: Check vmagent status
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (s *Server) vpnStatusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	status := s.vpnManager.GetStatus()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

func (s *Server) vpnConnectHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := s.vpnManager.Connect(); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ErrorResponse{Error: err.Error()})
		return
	}

	status := s.vpnManager.GetStatus()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

func (s *Server) vpnDisconnectHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := s.vpnManager.Disconnect(); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ErrorResponse{Error: err.Error()})
		return
	}

	status := s.vpnManager.GetStatus()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}
