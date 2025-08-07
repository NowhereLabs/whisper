#!/usr/bin/env python3
"""
Windows Automation Sidecar Container
Provides HTTP API for Windows typing automation from WSL/Docker
"""

from flask import Flask, request, jsonify
import subprocess
import shlex
import os
import logging
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

class WindowsAutomation:
    """Handle Windows automation through PowerShell"""
    
    def __init__(self):
        self.available = self._check_powershell()
    
    def _check_powershell(self):
        """Check if PowerShell is accessible"""
        try:
            # Try PowerShell via different paths
            powershell_paths = [
                'powershell.exe',
                '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe',
                '/usr/local/bin/powershell'  # Our wrapper script in container
            ]
            
            for ps_path in powershell_paths:
                try:
                    result = subprocess.run([ps_path, '-Command', 'Write-Output "test"'], 
                                          capture_output=True, timeout=5)
                    if result.returncode == 0:
                        logger.info(f"PowerShell found at: {ps_path}")
                        self.powershell_path = ps_path
                        return True
                except:
                    continue
            
            logger.info("PowerShell not found via direct execution")
            return False
        except Exception as e:
            logger.info(f"PowerShell check failed: {e}")
            return False
    
    def type_text(self, text, delay_ms=50):
        """Type text into Windows applications"""
        if not self.available:
            return False, "PowerShell not available"
        
        try:
            # Escape special characters for SendKeys
            escaped_text = self._escape_sendkeys(text)
            
            ps_command = f'''
            Add-Type -AssemblyName System.Windows.Forms
            Start-Sleep -Milliseconds {delay_ms}
            [System.Windows.Forms.SendKeys]::SendWait("{escaped_text}")
            '''
            
            result = subprocess.run([
                getattr(self, 'powershell_path', 'powershell.exe'), '-Command', ps_command
            ], capture_output=True, timeout=10)
            
            success = result.returncode == 0
            error_msg = result.stderr.decode() if result.stderr else None
            
            return success, error_msg
        except Exception as e:
            return False, str(e)
    
    def _escape_sendkeys(self, text):
        """Escape special characters for SendKeys"""
        # SendKeys special characters that need escaping
        special_chars = {
            '+': '{+}',
            '^': '{^}',
            '%': '{%}',
            '~': '{~}',
            '(': '{(}',
            ')': '{)}',
            '{': '{{}',
            '}': '{}}',
            '[': '{[}',
            ']': '{]}'
        }
        
        escaped = text
        for char, escape in special_chars.items():
            escaped = escaped.replace(char, escape)
            
        return escaped

# Create automation instance
windows_automation = WindowsAutomation()

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'powershell_available': windows_automation.available,
        'timestamp': time.time()
    })

@app.route('/type', methods=['POST'])
def type_text():
    """Type text endpoint"""
    try:
        data = request.get_json()
        if not data or 'text' not in data:
            return jsonify({'error': 'Missing text parameter'}), 400
        
        text = data['text']
        delay_ms = data.get('delay_ms', 50)
        
        logger.info(f"Typing request: '{text[:50]}...' with {delay_ms}ms delay")
        
        success, error_msg = windows_automation.type_text(text, delay_ms)
        
        if success:
            return jsonify({
                'status': 'success',
                'message': f'Typed {len(text)} characters',
                'text_length': len(text)
            })
        else:
            logger.error(f"Typing failed: {error_msg}")
            return jsonify({
                'status': 'error',
                'message': error_msg or 'Unknown error'
            }), 500
    except Exception as e:
        logger.error(f"Typing endpoint error: {e}")
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/status', methods=['GET'])
def status():
    """Service status endpoint"""
    return jsonify({
        'service': 'Windows Automation Sidecar',
        'powershell_available': windows_automation.available,
        'powershell_path': getattr(windows_automation, 'powershell_path', 'N/A'),
        'endpoints': ['/health', '/type', '/status']
    })

if __name__ == '__main__':
    logger.info("Starting Windows Automation Sidecar...")
    logger.info(f"PowerShell available: {windows_automation.available}")
    
    app.run(host='0.0.0.0', port=8080, debug=False)