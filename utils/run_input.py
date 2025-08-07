#!/usr/bin/env python3
"""
Windows Automation Sidecar Client
Communicates with WSL host sidecar service for Windows typing automation
"""

import requests
import os
import sys
import time

class WindowsAutomationClient:
    """Client for Windows automation sidecar service"""
    
    def __init__(self):
        self.sidecar_url = os.environ.get('WINDOWS_AUTOMATION_URL', 'http://host.docker.internal:8080')
        self.available = self._check_sidecar_availability()
    
    def _check_sidecar_availability(self):
        """Check if Windows automation sidecar is available"""
        try:
            response = requests.get(f"{self.sidecar_url}/health", timeout=3)
            if response.status_code == 200:
                health_data = response.json()
                return (health_data.get('status') == 'healthy' and 
                       health_data.get('powershell_available', False))
            return False
        except Exception as e:
            print(f"⚠️  Cannot connect to Windows automation service: {e}")
            return False
    
    def type_text(self, text, delay_ms=50):
        """Type text using Windows automation sidecar service"""
        if not self.available:
            print("❌ Windows automation sidecar not available")
            return False
            
        try:
            payload = {
                'text': text,
                'delay_ms': delay_ms
            }
            response = requests.post(f"{self.sidecar_url}/type", json=payload, timeout=30)
            
            if response.status_code == 200:
                result = response.json()
                return result.get('status') == 'success'
            else:
                try:
                    error_data = response.json()
                    print(f"❌ Sidecar error: {error_data.get('message', 'Unknown error')}")
                except:
                    print(f"❌ Sidecar HTTP error: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Sidecar communication error: {e}")
            return False

# Legacy compatibility class
class WSLWindowsTyper(WindowsAutomationClient):
    """Legacy compatibility wrapper"""
    
    def __init__(self):
        super().__init__()
        self.method = "sidecar" if self.available else None

def main():
    """Test the Windows automation client"""
    client = WindowsAutomationClient()
    
    if len(sys.argv) > 1:
        text = ' '.join(sys.argv[1:])
    else:
        text = "Hello from Windows automation sidecar!"
    
    print(f"🎯 Sidecar URL: {client.sidecar_url}")
    print(f"🎯 Service available: {client.available}")
    print(f"⌨️  Typing: {text}")
    
    success = client.type_text(text)
    if success:
        print("✅ Text typed successfully!")
    else:
        print("❌ Failed to type text")

if __name__ == "__main__":
    main()