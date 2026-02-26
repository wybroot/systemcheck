import os
import re
import subprocess
import threading
from datetime import datetime
from flask import current_app
from .. import db
from ..models import Server, Inspection, InspectionItem, Alert

class InspectorService:
    
    @staticmethod
    def parse_inspection_output(output):
        result = {
            'system': {},
            'cpu': {},
            'memory': {},
            'disk': {},
            'network': {},
            'process': {},
            'security': {},
            'status': 'OK',
            'warnings': [],
            'criticals': []
        }
        
        current_section = None
        for line in output.split('\n'):
            line = line.strip()
            
            if line == '===SYSTEM===':
                current_section = 'system'
            elif line == '===CPU===':
                current_section = 'cpu'
            elif line == '===MEMORY===':
                current_section = 'memory'
            elif line == '===DISK===':
                current_section = 'disk'
            elif line == '===NETWORK===':
                current_section = 'network'
            elif line == '===PROCESS===':
                current_section = 'process'
            elif line == '===SECURITY===':
                current_section = 'security'
            elif line == '===INSPECT_END===':
                break
            elif '=' in line and current_section:
                match = re.match(r'^([A-Z_]+)=(.*)$', line)
                if match:
                    key = match.group(1)
                    value = match.group(2)
                    result[current_section][key] = value
                    
                    if key.endswith('_STATUS'):
                        if value == 'CRITICAL':
                            result['status'] = 'CRITICAL'
                        elif value == 'WARNING' and result['status'] != 'CRITICAL':
                            result['status'] = 'WARNING'
                    
                    if key.endswith('_WARNINGS') and value:
                        result['warnings'].append(value)
                    elif key.endswith('_CRITICALS') and value:
                        result['criticals'].append(value)
        
        return result
    
    @staticmethod
    def run_inspection(server_id, callback=None):
        from .. import create_app
        app = create_app()
        
        with app.app_context():
            server = Server.query.get(server_id)
            if not server:
                if callback:
                    callback(None, 'Server not found')
                return None, 'Server not found'
            
            start_time = datetime.utcnow()
            
            try:
                script_path = current_app.config.get('INSPECT_SCRIPT_PATH', 'inspect.sh')
                timeout = current_app.config.get('INSPECT_TIMEOUT', 300)
                
                env = os.environ.copy()
                env['SERVERS_FILE'] = ''
                
                cmd = [
                    script_path,
                    server.ip
                ]
                
                process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=env,
                    cwd=os.path.dirname(script_path)
                )
                
                try:
                    stdout, stderr = process.communicate(timeout=timeout)
                    output = stdout.decode('utf-8', errors='ignore')
                    error = stderr.decode('utf-8', errors='ignore')
                except subprocess.TimeoutExpired:
                    process.kill()
                    if callback:
                        callback(None, 'Inspection timeout')
                    return None, 'Inspection timeout'
                
                end_time = datetime.utcnow()
                duration = (end_time - start_time).total_seconds()
                
                parsed = InspectorService.parse_inspection_output(output)
                
                inspection = Inspection(
                    server_id=server.id,
                    inspection_time=start_time,
                    cpu_usage=parsed['cpu'].get('CPU_USAGE'),
                    cpu_load_1min=parsed['cpu'].get('LOAD_1MIN'),
                    cpu_load_5min=parsed['cpu'].get('LOAD_5MIN'),
                    cpu_load_15min=parsed['cpu'].get('LOAD_15MIN'),
                    memory_usage=parsed['memory'].get('MEM_USAGE'),
                    memory_used=parsed['memory'].get('MEM_USED'),
                    memory_total=parsed['memory'].get('MEM_TOTAL'),
                    swap_usage=parsed['memory'].get('SWAP_USAGE'),
                    disk_usage=parsed['disk'].get('DISK_USAGE'),
                    connection_count=parsed['network'].get('CONNECTION_COUNT'),
                    zombie_count=parsed['process'].get('ZOMBIE_COUNT'),
                    status=parsed['status'],
                    duration=int(duration)
                )
                
                db.session.add(inspection)
                db.session.flush()
                
                for section in ['system', 'cpu', 'memory', 'disk', 'network', 'process', 'security']:
                    section_data = parsed.get(section, {})
                    for key, value in section_data.items():
                        if not key.endswith('_STATUS') and not key.endswith('_RESULT') and not key.endswith('_WARNINGS') and not key.endswith('_CRITICALS'):
                            item = InspectionItem(
                                inspection_id=inspection.id,
                                category=section,
                                check_item=key,
                                check_value=value,
                                status=section_data.get(f"{key.split('_')[0]}_STATUS", 'OK')
                            )
                            db.session.add(item)
                
                if parsed['criticals']:
                    for critical in parsed['criticals']:
                        if critical:
                            alert = Alert(
                                server_id=server.id,
                                inspection_id=inspection.id,
                                alert_type='INSPECTION',
                                alert_level='CRITICAL',
                                alert_content=critical,
                                status='PENDING'
                            )
                            db.session.add(alert)
                
                if parsed['warnings']:
                    for warning in parsed['warnings']:
                        if warning:
                            alert = Alert(
                                server_id=server.id,
                                inspection_id=inspection.id,
                                alert_type='INSPECTION',
                                alert_level='WARNING',
                                alert_content=warning,
                                status='PENDING'
                            )
                            db.session.add(alert)
                
                db.session.commit()
                
                if callback:
                    callback(inspection.to_dict(), None)
                
                return inspection.to_dict(), None
                
            except Exception as e:
                db.session.rollback()
                if callback:
                    callback(None, str(e))
                return None, str(e)
    
    @staticmethod
    def run_batch_inspection(server_ids, callback=None):
        results = {
            'success': [],
            'failed': []
        }
        
        for server_id in server_ids:
            result, error = InspectorService.run_inspection(server_id)
            if error:
                results['failed'].append({'server_id': server_id, 'error': error})
            else:
                results['success'].append(result)
        
        if callback:
            callback(results)
        
        return results
    
    @staticmethod
    def run_inspection_async(server_id, callback=None):
        thread = threading.Thread(
            target=InspectorService.run_inspection,
            args=(server_id, callback)
        )
        thread.daemon = True
        thread.start()
        return thread
    
    @staticmethod
    def run_batch_inspection_async(server_ids, callback=None):
        thread = threading.Thread(
            target=InspectorService.run_batch_inspection,
            args=(server_ids, callback)
        )
        thread.daemon = True
        thread.start()
        return thread