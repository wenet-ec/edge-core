// edge_vpn/main.go
package main

import (
	"edge_vpn/internal/keymanager"
	"encoding/json"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type Server struct {
	keyManager      *keymanager.Manager
	rotationService *keymanager.RotationService
	headscaleProxy  *httputil.ReverseProxy
}

type HealthResponse struct {
	Status  string `json:"status"`
	Service string `json:"service"`
	Version string `json:"version"`
}

type KeyStatusResponse struct {
	Status    string                 `json:"status"`
	KeyInfo   map[string]interface{} `json:"key_info"`
	Timestamp string                 `json:"timestamp"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}

	// Initialize key manager
	keyManager := keymanager.NewManager("")
	if err := keyManager.Initialize(); err != nil {
		log.Fatalf("Failed to initialize key manager: %v", err)
	}

	// Start rotation service
	rotationService := keymanager.NewRotationService(keyManager)
	if err := rotationService.Start(); err != nil {
		log.Fatalf("Failed to start rotation service: %v", err)
	}

	// Setup Headscale proxy
	headscaleURL, err := url.Parse("http://localhost:8080")
	if err != nil {
		log.Fatalf("Failed to parse Headscale URL: %v", err)
	}

	server := &Server{
		keyManager:      keyManager,
		rotationService: rotationService,
		headscaleProxy:  httputil.NewSingleHostReverseProxy(headscaleURL),
	}

	// Setup router
	r := chi.NewRouter()

	// Middleware
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.RequestID)
	r.Use(middleware.Timeout(30 * time.Second))

	// Wrapper service endpoints (not proxied)
	r.Get("/health", server.healthHandler)
	r.Get("/key-status", server.keyStatusHandler)
	r.Post("/force-rotation", server.forceRotationHandler)

	// Proxy all other requests to Headscale with API key
	r.HandleFunc("/*", server.proxyHandler)

	// Graceful shutdown
	go func() {
		log.Printf("Starting Edge VPN Wrapper on port %s", port)
		if err := http.ListenAndServe(":"+port, r); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")
	rotationService.Stop()
	log.Println("Server shutdown complete")
}

// healthHandler returns the health status of the wrapper service
func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	// Check if we can get a valid API key
	_, err := s.keyManager.GetCurrentKey()
	status := "ok"
	if err != nil {
		status = "degraded"
		w.WriteHeader(http.StatusServiceUnavailable)
	}

	json.NewEncoder(w).Encode(HealthResponse{
		Status:  status,
		Service: "edge-vpn-wrapper",
		Version: "0.0.1",
	})
}

// keyStatusHandler returns detailed information about the current API key
func (s *Server) keyStatusHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	keyInfo := s.keyManager.GetKeyInfo()

	response := KeyStatusResponse{
		Status:    "ok",
		KeyInfo:   keyInfo,
		Timestamp: time.Now().Format(time.RFC3339),
	}

	// Set appropriate HTTP status based on key status
	if keyInfo["status"] == "no_key" || keyInfo["is_expired"] == true {
		w.WriteHeader(http.StatusServiceUnavailable)
		response.Status = "error"
	} else if keyInfo["needs_rotation"] == true {
		w.WriteHeader(http.StatusAccepted)
		response.Status = "warning"
	}

	json.NewEncoder(w).Encode(response)
}

// forceRotationHandler manually triggers key rotation
func (s *Server) forceRotationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	log.Println("Force rotation requested via API")

	if err := s.rotationService.ForceRotation(); err != nil {
		log.Printf("Force rotation failed: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{
			"status": "error",
			"error":  err.Error(),
		})
		return
	}

	json.NewEncoder(w).Encode(map[string]string{
		"status":  "success",
		"message": "Key rotation completed successfully",
	})
}

// proxyHandler forwards requests to Headscale with the API key attached
func (s *Server) proxyHandler(w http.ResponseWriter, r *http.Request) {
	// Get current API key
	apiKey, err := s.keyManager.GetCurrentKey()
	if err != nil {
		log.Printf("Failed to get API key for request: %v", err)
		http.Error(w, "API key not available", http.StatusServiceUnavailable)
		return
	}

	// Clone the request to modify headers
	proxyReq := r.Clone(r.Context())

	// Add the API key to Authorization header
	proxyReq.Header.Set("Authorization", "Bearer "+apiKey)

	// Set the request URL to point to Headscale
	proxyReq.URL.Scheme = "http"
	proxyReq.URL.Host = "localhost:8080"
	proxyReq.RequestURI = ""

	// Log the proxied request (for debugging)
	log.Printf("Proxying %s %s to Headscale", r.Method, r.URL.Path)

	// Use a custom director for the reverse proxy
	originalDirector := s.headscaleProxy.Director
	s.headscaleProxy.Director = func(req *http.Request) {
		originalDirector(req)
		// Add the API key header
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}

	// Handle the proxy request
	s.headscaleProxy.ServeHTTP(w, r)
}
