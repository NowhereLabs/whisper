from whisper_live.client import TranscriptionClient
import argparse
import sys
import datetime
import threading
import logging
import os
import json
import time

class TranscriptionLogger:
    """Comprehensive logging system for transcription analysis"""
    
    def __init__(self, log_dir="/output", enable_json=True, enable_text=True, verbose=False):
        self.log_dir = log_dir
        self.enable_json = enable_json
        self.enable_text = enable_text
        self.verbose = verbose
        self.session_id = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Create log directory with proper permissions (readable/writable by all)
        os.makedirs(log_dir, mode=0o755, exist_ok=True)
        # Try to set ownership to current user if we're root
        try:
            import pwd
            import grp
            # Get the real user ID from environment or fall back to current user
            real_uid = int(os.environ.get('SUDO_UID', os.getuid()))
            real_gid = int(os.environ.get('SUDO_GID', os.getgid()))
            if os.getuid() == 0 and real_uid != 0:  # Running as root but have real user info
                os.chown(log_dir, real_uid, real_gid)
        except (KeyError, ValueError, OSError):
            pass  # Ignore permission errors
        
        # JSON log for structured data
        if self.enable_json:
            self.json_log_path = os.path.join(log_dir, f"transcription_{self.session_id}.json")
            self.json_segments = []
        
        # Text log for human-readable output
        if self.enable_text:
            self.text_log_path = os.path.join(log_dir, f"transcription_{self.session_id}.log")
            with open(self.text_log_path, 'w', encoding='utf-8') as f:
                f.write(f"WhisperLive Transcription Log\n")
                f.write(f"Session: {self.session_id}\n")
                f.write(f"Started: {datetime.datetime.now().isoformat()}\n")
                f.write("="*80 + "\n\n")
            # Set file permissions to be readable/writable by owner and readable by others
            os.chmod(self.text_log_path, 0o644)
            # Try to set ownership to real user if running as root
            try:
                real_uid = int(os.environ.get('SUDO_UID', os.getuid()))
                real_gid = int(os.environ.get('SUDO_GID', os.getgid()))
                if os.getuid() == 0 and real_uid != 0:
                    os.chown(self.text_log_path, real_uid, real_gid)
            except (KeyError, ValueError, OSError):
                pass
        
        # Statistics tracking
        self.stats = {
            "total_segments": 0,
            "completed_segments": 0,
            "incomplete_segments": 0,
            "total_duration": 0,
            "total_words": 0,
            "vad_triggers": 0,
            "segment_sizes": [],
            "segment_durations": [],
            "processing_times": [],
            "silence_periods": []
        }
        
        self.last_segment_time = time.time()
        self.lock = threading.Lock()
    
    def log_segment(self, segment_data, segment_type="transcription"):
        """Log a transcription segment with metadata"""
        with self.lock:
            timestamp = datetime.datetime.now()
            current_time = time.time()
            
            # Calculate time since last segment
            time_since_last = current_time - self.last_segment_time
            self.last_segment_time = current_time
            
            # Prepare segment info
            segment_info = {
                "timestamp": timestamp.isoformat(),
                "type": segment_type,
                "segment_index": self.stats["total_segments"],
                "time_since_last": round(time_since_last, 3),
                "data": segment_data
            }
            
            # Update statistics
            self.stats["total_segments"] += 1
            if segment_data.get("completed", False):
                self.stats["completed_segments"] += 1
            else:
                self.stats["incomplete_segments"] += 1
            
            if "text" in segment_data:
                word_count = len(segment_data["text"].split())
                self.stats["total_words"] += word_count
                segment_info["word_count"] = word_count
            
            if "start" in segment_data and "end" in segment_data:
                try:
                    start_time = float(segment_data["start"])
                    end_time = float(segment_data["end"])
                    duration = end_time - start_time
                    self.stats["segment_durations"].append(duration)
                    segment_info["duration"] = round(duration, 3)
                    self.stats["total_duration"] = max(self.stats["total_duration"], end_time)
                except (ValueError, TypeError):
                    # Handle case where start/end are not numeric
                    pass
            
            # Write to JSON log
            if self.enable_json:
                self.json_segments.append(segment_info)
                # Write incrementally to avoid data loss
                with open(self.json_log_path, 'w', encoding='utf-8') as f:
                    json.dump({
                        "session_id": self.session_id,
                        "stats": self.stats,
                        "segments": self.json_segments
                    }, f, indent=2, ensure_ascii=False)
                # Set file permissions
                os.chmod(self.json_log_path, 0o644)
                # Try to set ownership to real user if running as root
                try:
                    real_uid = int(os.environ.get('SUDO_UID', os.getuid()))
                    real_gid = int(os.environ.get('SUDO_GID', os.getgid()))
                    if os.getuid() == 0 and real_uid != 0:
                        os.chown(self.json_log_path, real_uid, real_gid)
                except (KeyError, ValueError, OSError):
                    pass
            
            # Write to text log
            if self.enable_text:
                with open(self.text_log_path, 'a', encoding='utf-8') as f:
                    f.write(f"\n[{timestamp.strftime('%H:%M:%S.%f')[:-3]}] ")
                    f.write(f"Segment #{self.stats['total_segments']} ")
                    f.write(f"({'COMPLETE' if segment_data.get('completed') else 'PARTIAL'}) ")
                    if "duration" in segment_info:
                        f.write(f"Duration: {segment_info['duration']}s ")
                    f.write(f"Gap: {time_since_last:.1f}s\n")
                    
                    if "text" in segment_data:
                        f.write(f"Text: {segment_data['text']}\n")
                    
                    if "start" in segment_data and "end" in segment_data:
                        try:
                            start_time = float(segment_data["start"])
                            end_time = float(segment_data["end"])
                            f.write(f"Timing: {start_time:.2f}s - {end_time:.2f}s\n")
                        except (ValueError, TypeError):
                            f.write(f"Timing: {segment_data['start']} - {segment_data['end']}\n")
                    
                    if self.verbose and "no_speech_prob" in segment_data:
                        f.write(f"No Speech Prob: {segment_data.get('no_speech_prob', 'N/A')}\n")
            
            return segment_info
    
    def log_vad_event(self, event_type, details=None):
        """Log VAD-related events"""
        with self.lock:
            self.stats["vad_triggers"] += 1
            timestamp = datetime.datetime.now()
            
            event_info = {
                "timestamp": timestamp.isoformat(),
                "type": "vad_event",
                "event": event_type,
                "details": details
            }
            
            if self.enable_json:
                self.json_segments.append(event_info)
            
            if self.enable_text and self.verbose:
                with open(self.text_log_path, 'a', encoding='utf-8') as f:
                    f.write(f"\n[{timestamp.strftime('%H:%M:%S.%f')[:-3]}] ")
                    f.write(f"VAD EVENT: {event_type}")
                    if details:
                        f.write(f" - {details}")
                    f.write("\n")
    
    def write_summary(self):
        """Write final summary statistics"""
        with self.lock:
            if self.stats["segment_durations"]:
                avg_duration = sum(self.stats["segment_durations"]) / len(self.stats["segment_durations"])
            else:
                avg_duration = 0
            
            summary = f"""
{"="*80}
TRANSCRIPTION SESSION SUMMARY
{"="*80}
Session ID: {self.session_id}
End Time: {datetime.datetime.now().isoformat()}

STATISTICS:
- Total Segments: {self.stats['total_segments']}
  - Completed: {self.stats['completed_segments']}
  - Incomplete: {self.stats['incomplete_segments']}
- Total Duration: {self.stats['total_duration']:.2f} seconds
- Total Words: {self.stats['total_words']}
- Average Segment Duration: {avg_duration:.2f} seconds
- VAD Triggers: {self.stats['vad_triggers']}

LOG FILES:
"""
            if self.enable_json:
                summary += f"- JSON: {self.json_log_path}\n"
            if self.enable_text:
                summary += f"- Text: {self.text_log_path}\n"
            
            summary += "="*80
            
            if self.enable_text:
                with open(self.text_log_path, 'a', encoding='utf-8') as f:
                    f.write(summary)
            
            print(summary)

def print_client_banner(args):
    """Print a professional client startup banner"""
    print("\n" + "="*80)
    print("                        WHISPERLIVE TRANSCRIPTION CLIENT")
    print("="*80)
    print(f"Server:       {args.server}:{args.port}")
    print(f"Model:        {args.model}")
    print(f"Language:     {args.lang}")
    if args.translate:
        print(f"Task:         Translation")
    else:
        print(f"Task:         Transcription")
    if args.enable_translation:
        print(f"Translation:  {args.target_language}")
    if args.trigger_words:
        print(f"Trigger Words: {', '.join(args.trigger_words)}")
        print(f"Trigger File:  {args.trigger_output_file}")
    print("="*80)
    print("🎤 Starting microphone capture...")
    print("💡 Press Ctrl+C to stop")
    print("")
    sys.stdout.flush()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', '-p',
                        type=int,
                        default=9090,
                        help="Websocket port to run the server on.")
    parser.add_argument('--server', '-s',
                        type=str,
                        default='localhost',
                        help='hostname or ip address of server')
    parser.add_argument('--output_file', '-o',
                        type=str,
                        default='./output_recording.wav',
                        help='output recording filename.')
    parser.add_argument('--model', '-m',
                        type=str,
                        default='small',
                        help='Model to use for transcription, e.g., "tiny, small.en, large-v3".')
    parser.add_argument('--lang', '-l',
                        type=str,
                        default='en',
                        help='Language code for transcription, e.g., "en" for English.')
    parser.add_argument('--translate', '-t',
                        action='store_true',
                        help='Enable translation of the transcription output.')
    parser.add_argument('--save_output_recording', '-r',
                        action='store_true',
                        help='Save the output recording.')
    parser.add_argument('--enable_translation',
                        action='store_true',
                        help='Enable translation of the transcription output.')
    parser.add_argument('--target_language', '-tl',
                        type=str,
                        default='fr',
                        help='Target language for translation, e.g., "fr" for French.')
    parser.add_argument('--trigger_words',
                        type=str,
                        nargs='+',
                        help='List of trigger words to monitor (e.g., --trigger_words "hello" "alert" "help")')
    parser.add_argument('--trigger_output_file',
                        type=str,
                        default='/output/trigger_detections.txt',
                        help='File to write transcriptions when trigger words are detected')
    parser.add_argument('--text_stability_delay',
                        type=float,
                        default=1.5,
                        help='Time in seconds to wait after text stops changing before saving (default: 1.5)')
    
    # VAD (Voice Activity Detection) Parameters
    parser.add_argument('--vad_threshold',
                        type=float,
                        default=0.5,
                        help='VAD speech detection sensitivity threshold (0.0-1.0). Lower=more sensitive (default: 0.5)')
    parser.add_argument('--vad_neg_threshold',
                        type=float,
                        help='VAD end-of-speech detection threshold (0.0-1.0). Default: auto-calculated')
    parser.add_argument('--vad_min_speech_duration_ms',
                        type=int,
                        default=250,
                        help='Minimum speech duration in milliseconds (0-5000). Shorter speech ignored (default: 250)')
    parser.add_argument('--vad_max_speech_duration_s',
                        type=int,
                        default=30,
                        help='Maximum speech duration in seconds (1-300). Longer speech split (default: 30)')
    parser.add_argument('--vad_min_silence_duration_ms',
                        type=int,
                        default=2000,
                        help='Required silence before ending speech in milliseconds (100-5000) (default: 2000)')
    parser.add_argument('--vad_speech_pad_ms',
                        type=int,
                        default=400,
                        help='Padding around detected speech in milliseconds (0-1000) (default: 400)')
    parser.add_argument('--vad_window_size_samples',
                        type=int,
                        default=64,
                        help='VAD analysis window size in samples (32-128) (default: 64)')
    parser.add_argument('--vad_return_seconds',
                        action='store_true',
                        help='Return timestamps in seconds instead of samples')
    
    # Logging Configuration Parameters
    parser.add_argument('--log_dir',
                        type=str,
                        default='./logs',
                        help='Directory for transcription logs (default: ./logs)')
    parser.add_argument('--disable_json_log',
                        action='store_true',
                        help='Disable JSON logging (enabled by default)')
    parser.add_argument('--disable_text_log',
                        action='store_true',
                        help='Disable text logging (enabled by default)')
    parser.add_argument('--log_verbose',
                        action='store_true',
                        help='Enable verbose logging with additional metadata')
    parser.add_argument('--disable_logging',
                        action='store_true',
                        help='Disable all transcription logging')

    args = parser.parse_args()

    print_client_banner(args)
    
    # Setup debug logging in the same directory as other logs
    debug_log_file = os.path.join(args.log_dir, 'trigger_debug.log')
    
    # Configure logging with explicit encoding
    logger = logging.getLogger('trigger_debug')
    logger.setLevel(logging.DEBUG)
    
    # Remove existing handlers
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
    
    # Create file handler
    try:
        # Ensure log directory exists
        os.makedirs(args.log_dir, mode=0o755, exist_ok=True)
        file_handler = logging.FileHandler(debug_log_file, mode='w', encoding='utf-8')
        file_handler.setLevel(logging.DEBUG)
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
        logger.info(f"Starting trigger word detection with words: {args.trigger_words}")
    except Exception as e:
        print(f"Warning: Could not setup debug logging: {e}")
        logger = None
    
    # Create a lock for thread-safe file writing
    file_lock = threading.Lock()
    
    # Improved trigger detection state with buffering approach
    trigger_state = {
        'waiting': False,
        'trigger_word': None,
        'trigger_position': -1,  # Word position within trigger segment text
        'trigger_segment_index': -1,
        'start_time': None,
        'last_change_time': None,
        'stability_delay': args.text_stability_delay,
        'last_saved_text': '',
        'cooldown_until': None,
        'last_processed_segment_count': 0,
        'waiting_segment_count': 0,
        'collection_timeout': 5.0,  # Collect segments for up to 5 seconds after trigger
        'max_collection_time': None  # Maximum time to collect after trigger
    }
    
    def trigger_word_callback(text, segments):
        """Simple trigger detection with segment count tracking"""
        if not args.trigger_words or not segments:
            return
            
        current_time = datetime.datetime.now()
        current_segment_count = len(segments)
        
        if logger:
            logger.debug(f"Callback: {current_segment_count} segments, processed_count: {trigger_state['last_processed_segment_count']}")
        
        # Check if we're in cooldown period
        if trigger_state['cooldown_until'] and current_time < trigger_state['cooldown_until']:
            if logger:
                logger.debug(f"In cooldown period, ignoring triggers")
            return
        
        # If we're waiting for complete utterance after trigger
        if trigger_state['waiting']:
            # Update collection timeout if this is the first time setting it
            if trigger_state['max_collection_time'] is None:
                trigger_state['max_collection_time'] = current_time + datetime.timedelta(seconds=trigger_state['collection_timeout'])
            
            # Check if new segments have arrived since we started waiting
            segments_changed = current_segment_count > trigger_state['waiting_segment_count']
            collection_timeout_reached = current_time >= trigger_state['max_collection_time']
            
            if segments_changed:
                trigger_state['last_change_time'] = current_time
                trigger_state['waiting_segment_count'] = current_segment_count
                if logger:
                    logger.debug(f"New segments arrived while collecting: {current_segment_count}")
                    for i, seg in enumerate(segments):
                        logger.debug(f"Buffered Segment {i}: '{seg.get('text', '')}'")
                    
            # Check if we should finalize the collection
            time_since_change = (current_time - trigger_state['last_change_time']).total_seconds() if trigger_state['last_change_time'] else 0
            stability_reached = time_since_change >= trigger_state['stability_delay']
            
            # Only finalize if collection timeout is reached OR if we have stable text AND it's been at least 2 seconds
            time_since_trigger = (current_time - trigger_state['start_time']).total_seconds() if trigger_state['start_time'] else 0
            minimum_collection_time = 2.0
            
            should_finalize = collection_timeout_reached or (stability_reached and time_since_trigger >= minimum_collection_time)
            
            if logger:
                logger.debug(f"Collection status - Stable: {stability_reached} ({time_since_change:.1f}s), Timeout: {collection_timeout_reached}, Time since trigger: {time_since_trigger:.1f}s, Finalizing: {should_finalize}")
                
            if should_finalize:
                # Extract text from all collected segments using improved buffering strategy
                if trigger_state['trigger_segment_index'] >= 0:
                    # Collect all text from all segments
                    all_text = ' '.join([s.get('text', '').strip() for s in segments])
                    trigger_word = trigger_state['trigger_word'].lower()
                    
                    if logger:
                        logger.debug(f"Text extraction - All collected text: '{all_text}'")
                        logger.debug(f"Text extraction - Looking for trigger: '{trigger_word}'")
                        logger.debug(f"Text extraction - Total segments collected: {len(segments)}")
                        for i, seg in enumerate(segments):
                            logger.debug(f"Segment {i}: '{seg.get('text', '')}'")
                    
                    # Find the LAST occurrence of trigger word in the complete text (most recent trigger)
                    trigger_pos = all_text.lower().rfind(trigger_word)
                    if trigger_pos >= 0:
                        # Extract everything after the LAST occurrence of the trigger word
                        post_trigger_text = all_text[trigger_pos + len(trigger_word):].strip()
                        # Clean up common artifacts
                        post_trigger_text = post_trigger_text.lstrip(' ,.!?')
                        
                        if logger:
                            logger.debug(f"Text extraction - Found LAST trigger at position {trigger_pos}")
                            logger.debug(f"Text extraction - Extracted post-trigger text: '{post_trigger_text}'")
                    else:
                        # Fallback: use segments after trigger segment
                        post_trigger_segments = segments[trigger_state['trigger_segment_index'] + 1:]
                        post_trigger_text = ' '.join([s.get('text', '').strip() for s in post_trigger_segments])
                        
                        if logger:
                            logger.debug(f"Text extraction - Trigger not found in combined text, using segment fallback")
                            logger.debug(f"Text extraction - Fallback post-trigger text: '{post_trigger_text}'")
                    
                    if logger:
                        logger.debug(f"Text extraction - Extracted text: '{post_trigger_text}'")
                        logger.debug(f"Text extraction - Text stripped: '{post_trigger_text.strip()}'")
                        logger.debug(f"Text extraction - Last saved: '{trigger_state['last_saved_text']}'")
                    
                    # Save if we have meaningful content
                    if (post_trigger_text.strip() and 
                        post_trigger_text.strip() not in ['.', ',', ''] and
                        post_trigger_text.strip() != trigger_state['last_saved_text']):
                        
                        with file_lock:
                            try:
                                file_dir = os.path.dirname(args.trigger_output_file)
                                if file_dir and not os.path.exists(file_dir):
                                    os.makedirs(file_dir, exist_ok=True)
                                
                                with open(args.trigger_output_file, 'a', encoding='utf-8') as f:
                                    timestamp = current_time.strftime("%Y-%m-%d %H:%M:%S")
                                    f.write(f"[{timestamp}] TRIGGER '{trigger_state['trigger_word']}' DETECTED:\n")
                                    f.write(f"{post_trigger_text.strip()}\n")
                                    f.write("-" * 80 + "\n")
                                    f.flush()
                                    os.fsync(f.fileno())
                                
                                print(f"\n⚠️  Trigger statement saved: '{post_trigger_text.strip()[:50]}{'...' if len(post_trigger_text.strip()) > 50 else ''}'")
                                if logger:
                                    logger.info(f"STATEMENT SAVED: '{post_trigger_text.strip()}'")
                                
                                trigger_state['last_saved_text'] = post_trigger_text.strip()
                                trigger_state['cooldown_until'] = current_time + datetime.timedelta(seconds=2.0)
                            except Exception as e:
                                if logger:
                                    logger.error(f"Failed to write to trigger file: {e}")
                
                # Reset state and "clear transcript" by updating processed count
                trigger_state['waiting'] = False
                trigger_state['trigger_word'] = None
                trigger_state['trigger_segment_index'] = -1
                trigger_state['trigger_position'] = -1
                trigger_state['start_time'] = None
                trigger_state['last_change_time'] = None
                trigger_state['max_collection_time'] = None
                trigger_state['last_processed_segment_count'] = current_segment_count  # "Clear" by advancing processed count
                
                if logger:
                    logger.debug(f"Trigger processed, advancing segment count to {current_segment_count}")
        else:
            # Look for triggers only in new segments (beyond last processed count)
            new_segments = segments[trigger_state['last_processed_segment_count']:]
            
            if new_segments and logger:
                logger.debug(f"Checking {len(new_segments)} new segments for triggers")
                
            for i, segment in enumerate(new_segments):
                actual_index = trigger_state['last_processed_segment_count'] + i
                segment_text = segment.get('text', '').strip()
                
                if not segment_text:
                    continue
                    
                # Check for trigger words in this segment
                for trigger_word in args.trigger_words:
                    if trigger_word.lower() in segment_text.lower():
                        # Start waiting for complete statement
                        trigger_state['waiting'] = True
                        trigger_state['trigger_word'] = trigger_word
                        trigger_state['trigger_segment_index'] = actual_index
                        trigger_state['start_time'] = current_time
                        trigger_state['last_change_time'] = current_time
                        trigger_state['waiting_segment_count'] = current_segment_count
                        
                        if logger:
                            logger.info(f"Trigger word '{trigger_word}' found in new segment {actual_index}! Waiting for complete statement...")
                        print(f"\n💡 Trigger word '{trigger_word}' detected! Listening for complete statement...")
                        return  # Process one trigger at a time
    
    # Initialize transcription logger
    transcription_logger = None
    if not args.disable_logging:
        transcription_logger = TranscriptionLogger(
            log_dir=args.log_dir,
            enable_json=not args.disable_json_log,  # Default True unless disabled
            enable_text=not args.disable_text_log,  # Default True unless disabled
            verbose=args.log_verbose
        )
        print(f"📝 Transcription logging enabled: {args.log_dir}")
        if transcription_logger.enable_json:
            print(f"   - JSON log: transcription_{transcription_logger.session_id}.json")
        if transcription_logger.enable_text:
            print(f"   - Text log: transcription_{transcription_logger.session_id}.log")
    
    # Create a combined callback that handles both trigger words and logging
    def combined_callback(text, segments):
        try:
            # Log all segments to transcription logger
            if transcription_logger:
                for seg in segments:
                    transcription_logger.log_segment(seg)
            
            # Handle trigger words if specified
            if args.trigger_words:
                trigger_word_callback(text, segments)
        except Exception as e:
            # Log detailed errors to file but don't show in CLI during transcription
            if transcription_logger and transcription_logger.enable_text:
                import traceback
                with open(transcription_logger.text_log_path, 'a', encoding='utf-8') as f:
                    f.write(f"\n[ERROR] Callback error: {e}\n")
                    f.write(f"Error type: {type(e).__name__}\n")
                    if transcription_logger.verbose:
                        f.write(f"Traceback:\n{traceback.format_exc()}\n")
                    f.write("-" * 50 + "\n")
            # Only show critical errors in CLI
            if "critical" in str(e).lower():
                print(f"[CRITICAL ERROR] {e}")
    
    # Use combined callback if we have logging or trigger words
    callback_func = combined_callback if (transcription_logger or args.trigger_words) else None
    
    if args.trigger_words:
        if logger:
            logger.info(f"Trigger words enabled: {args.trigger_words}")
            logger.info(f"Output file: {args.trigger_output_file}")
            logger.info(f"Debug log file: {debug_log_file}")
        print(f"📝 Debug logging to: {debug_log_file}")
        print(f"🎯 Trigger words: {', '.join(args.trigger_words)}")
        print(f"⏱️  Text stability delay: {args.text_stability_delay}s")
        
        # Write startup info to debug log immediately
        try:
            os.makedirs(args.log_dir, mode=0o755, exist_ok=True)
            with open(debug_log_file, 'w', encoding='utf-8') as f:
                f.write(f"STARTUP: {datetime.datetime.now()}\n")
                f.write(f"Trigger words: {args.trigger_words}\n")
                f.write(f"Text stability delay: {trigger_state['stability_delay']}s\n")
                f.write("="*50 + "\n")
                f.flush()
        except Exception as e:
            print(f"Warning: Could not create debug log: {e}")
    
    # Build VAD parameters dictionary from command line arguments
    vad_parameters = {}
    if args.vad_threshold != 0.5:  # Only include non-default values
        vad_parameters["threshold"] = args.vad_threshold
    if args.vad_neg_threshold is not None:
        vad_parameters["neg_threshold"] = args.vad_neg_threshold
    if args.vad_min_speech_duration_ms != 250:
        vad_parameters["min_speech_duration_ms"] = args.vad_min_speech_duration_ms
    if args.vad_max_speech_duration_s != 30:
        vad_parameters["max_speech_duration_s"] = args.vad_max_speech_duration_s
    if args.vad_min_silence_duration_ms != 2000:
        vad_parameters["min_silence_duration_ms"] = args.vad_min_silence_duration_ms
    if args.vad_speech_pad_ms != 400:
        vad_parameters["speech_pad_ms"] = args.vad_speech_pad_ms
    if args.vad_window_size_samples != 64:
        vad_parameters["window_size_samples"] = args.vad_window_size_samples
    if args.vad_return_seconds:
        vad_parameters["return_seconds"] = True
    
    # Only pass vad_parameters if we have custom settings
    vad_params_to_use = vad_parameters if vad_parameters else None
    
    if vad_params_to_use:
        print(f"🎛️  Custom VAD settings: {vad_params_to_use}")
    
    client = TranscriptionClient(
        args.server,
        args.port,
        lang=args.lang,
        translate=args.translate,
        model=args.model,
        use_vad=True,
        save_output_recording=args.save_output_recording,
        output_recording_filename=args.output_file,
        enable_translation=args.enable_translation,
        target_language=args.target_language,
        transcription_callback=callback_func,
        log_transcription=True,  # Always show transcriptions
        vad_parameters=vad_params_to_use,
    )
    
    # Use microphone input
    try:
        client()
    except KeyboardInterrupt:
        print("\n\n🛑 Transcription stopped by user")
    except Exception as e:
        print(f"\n❌ Error during transcription: {e}")
    finally:
        # Write summary if logging was enabled
        if transcription_logger:
            transcription_logger.write_summary()