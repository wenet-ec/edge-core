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
	"sync/atomic"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type Server struct {
	keyManager      *keymanager.Manager
	rotationService *keymanager.RotationService
	headscaleProxy  *httputil.ReverseProxy
	ready           int32 // atomic flag for readiness
}

type HealthResponse struct {
	Status  string `json:"status"`
	Service string `json:"service"`
	Version string `json:"version"`
	Ready   bool   `json:"ready"`
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
	r.Get("/readiness", server.readinessHandler)
	r.Get("/key-status", server.keyStatusHandler)
	r.Post("/force-rotation", server.forceRotationHandler)

	// Proxy all other requests to Headscale with API key
	r.HandleFunc("/*", server.proxyHandler)

	// Start the HTTP server in a goroutine
	go func() {
		log.Printf("Starting Edge VPN Wrapper on port %s", port)
		if err := http.ListenAndServe(":"+port, r); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	// Give services a moment to start, then mark as ready
	go func() {
		time.Sleep(2 * time.Second)

		// Verify everything is working before marking ready
		if _, err := keyManager.GetCurrentKey(); err != nil {
			log.Printf("Key manager not ready: %v", err)
			return
		}

		// Test if we can reach Headscale
		testURL := "http://localhost:8080/health"
		resp, err := http.Get(testURL)
		if err != nil {
			log.Printf("Headscale not ready: %v", err)
			return
		}
		resp.Body.Close()

		atomic.StoreInt32(&server.ready, 1)
		log.Println("All services ready - health check will now return OK")
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")
	rotationService.Stop()
	log.Println("Server shutdown complete")
}

// healthHandler returns the health status - only OK when everything is ready
func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	isReady := atomic.LoadInt32(&s.ready) == 1

	response := HealthResponse{
		Service: "edge-vpn-wrapper",
		Version: "0.0.1",
		Ready:   isReady,
	}

	if !isReady {
		response.Status = "starting"
		w.WriteHeader(http.StatusServiceUnavailable)
	} else {
		// Additional check: ensure we still have a valid key
		_, err := s.keyManager.GetCurrentKey()
		if err != nil {
			response.Status = "degraded"
			response.Ready = false
			w.WriteHeader(http.StatusServiceUnavailable)
		} else {
			response.Status = "ok"
		}
	}

	json.NewEncoder(w).Encode(response)
}

// readinessHandler is a separate endpoint for readiness checks (if needed)
func (s *Server) readinessHandler(w http.ResponseWriter, r *http.Request) {
	if atomic.LoadInt32(&s.ready) == 1 {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ready"))
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("not ready"))
	}
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
			"error": "Rotation failed: " + err.Error(),
		})
		return
	}

	log.Println("Force rotation completed successfully")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Rotation completed successfully",
	})
}

// proxyHandler forwards requests to Headscale with authentication
func (s *Server) proxyHandler(w http.ResponseWriter, r *http.Request) {
	// Get current API key
	apiKey, err := s.keyManager.GetCurrentKey()
	if err != nil {
		log.Printf("Failed to get API key for request: %v", err)
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{
			"error": "Service temporarily unavailable",
		})
		return
	}

	// Add API key to request
	r.Header.Set("Authorization", "Bearer "+apiKey)

	// Forward to Headscale
	s.headscaleProxy.ServeHTTP(w, r)
}
