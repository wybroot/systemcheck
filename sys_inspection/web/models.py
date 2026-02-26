from datetime import datetime
from . import db

class Server(db.Model):
    __tablename__ = 'servers'
    
    id = db.Column(db.Integer, primary_key=True)
    hostname = db.Column(db.String(64), nullable=False)
    ip = db.Column(db.String(15), nullable=False, unique=True)
    ssh_port = db.Column(db.Integer, default=22)
    ssh_user = db.Column(db.String(32), default='root')
    os_type = db.Column(db.String(32))
    os_version = db.Column(db.String(64))
    cpu_cores = db.Column(db.Integer)
    memory_total = db.Column(db.Integer)
    disk_total = db.Column(db.Integer)
    business = db.Column(db.String(128))
    env = db.Column(db.String(32))
    services = db.Column(db.Text)
    tags = db.Column(db.Text)
    status = db.Column(db.SmallInteger, default=1)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    inspections = db.relationship('Inspection', backref='server', lazy='dynamic')
    alerts = db.relationship('Alert', backref='server', lazy='dynamic')
    
    def to_dict(self):
        return {
            'id': self.id,
            'hostname': self.hostname,
            'ip': self.ip,
            'ssh_port': self.ssh_port,
            'ssh_user': self.ssh_user,
            'os_type': self.os_type,
            'os_version': self.os_version,
            'cpu_cores': self.cpu_cores,
            'memory_total': self.memory_total,
            'disk_total': self.disk_total,
            'business': self.business,
            'env': self.env,
            'services': self.services,
            'tags': self.tags,
            'status': self.status,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }


class Inspection(db.Model):
    __tablename__ = 'inspections'
    
    id = db.Column(db.Integer, primary_key=True)
    server_id = db.Column(db.Integer, db.ForeignKey('servers.id'), nullable=False)
    inspection_time = db.Column(db.DateTime, default=datetime.utcnow)
    
    cpu_usage = db.Column(db.Numeric(5, 2))
    cpu_load_1min = db.Column(db.Numeric(6, 2))
    cpu_load_5min = db.Column(db.Numeric(6, 2))
    cpu_load_15min = db.Column(db.Numeric(6, 2))
    
    memory_usage = db.Column(db.Numeric(5, 2))
    memory_used = db.Column(db.Integer)
    memory_total = db.Column(db.Integer)
    swap_usage = db.Column(db.Numeric(5, 2))
    
    disk_usage = db.Column(db.Numeric(5, 2))
    
    connection_count = db.Column(db.Integer)
    zombie_count = db.Column(db.Integer)
    
    status = db.Column(db.String(16), default='OK')
    report_path = db.Column(db.String(256))
    report_file_id = db.Column(db.String(64))
    duration = db.Column(db.Integer)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    items = db.relationship('InspectionItem', backref='inspection', lazy='dynamic', cascade='all, delete-orphan')
    alerts = db.relationship('Alert', backref='inspection', lazy='dynamic')
    
    def to_dict(self):
        return {
            'id': self.id,
            'server_id': self.server_id,
            'server_hostname': self.server.hostname if self.server else None,
            'inspection_time': self.inspection_time.isoformat() if self.inspection_time else None,
            'cpu_usage': float(self.cpu_usage) if self.cpu_usage else None,
            'cpu_load_1min': float(self.cpu_load_1min) if self.cpu_load_1min else None,
            'cpu_load_5min': float(self.cpu_load_5min) if self.cpu_load_5min else None,
            'cpu_load_15min': float(self.cpu_load_15min) if self.cpu_load_15min else None,
            'memory_usage': float(self.memory_usage) if self.memory_usage else None,
            'memory_used': self.memory_used,
            'memory_total': self.memory_total,
            'swap_usage': float(self.swap_usage) if self.swap_usage else None,
            'disk_usage': float(self.disk_usage) if self.disk_usage else None,
            'connection_count': self.connection_count,
            'zombie_count': self.zombie_count,
            'status': self.status,
            'duration': self.duration,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }


class InspectionItem(db.Model):
    __tablename__ = 'inspection_items'
    
    id = db.Column(db.Integer, primary_key=True)
    inspection_id = db.Column(db.Integer, db.ForeignKey('inspections.id'), nullable=False)
    category = db.Column(db.String(32), nullable=False)
    check_item = db.Column(db.String(64))
    check_value = db.Column(db.Text)
    threshold = db.Column(db.String(32))
    status = db.Column(db.String(16), default='OK')
    message = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def to_dict(self):
        return {
            'id': self.id,
            'inspection_id': self.inspection_id,
            'category': self.category,
            'check_item': self.check_item,
            'check_value': self.check_value,
            'threshold': self.threshold,
            'status': self.status,
            'message': self.message,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }


class Alert(db.Model):
    __tablename__ = 'alerts'
    
    id = db.Column(db.Integer, primary_key=True)
    server_id = db.Column(db.Integer, db.ForeignKey('servers.id'))
    inspection_id = db.Column(db.Integer, db.ForeignKey('inspections.id'))
    alert_type = db.Column(db.String(32), nullable=False)
    alert_level = db.Column(db.String(16), nullable=False)
    alert_content = db.Column(db.Text)
    status = db.Column(db.String(16), default='PENDING')
    notify_status = db.Column(db.String(16), default='NONE')
    notify_time = db.Column(db.DateTime)
    handle_time = db.Column(db.DateTime)
    handler = db.Column(db.String(32))
    remark = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def to_dict(self):
        return {
            'id': self.id,
            'server_id': self.server_id,
            'server_hostname': self.server.hostname if self.server else None,
            'inspection_id': self.inspection_id,
            'alert_type': self.alert_type,
            'alert_level': self.alert_level,
            'alert_content': self.alert_content,
            'status': self.status,
            'notify_status': self.notify_status,
            'notify_time': self.notify_time.isoformat() if self.notify_time else None,
            'handle_time': self.handle_time.isoformat() if self.handle_time else None,
            'handler': self.handler,
            'remark': self.remark,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }


class Setting(db.Model):
    __tablename__ = 'settings'
    
    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.String(64), unique=True, nullable=False)
    value = db.Column(db.Text)
    description = db.Column(db.String(256))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    def to_dict(self):
        return {
            'id': self.id,
            'key': self.key,
            'value': self.value,
            'description': self.description,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }


class AuditLog(db.Model):
    __tablename__ = 'audit_logs'
    
    id = db.Column(db.Integer, primary_key=True)
    user = db.Column(db.String(32))
    action = db.Column(db.String(32), nullable=False)
    target = db.Column(db.String(64))
    detail = db.Column(db.Text)
    ip = db.Column(db.String(45))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def to_dict(self):
        return {
            'id': self.id,
            'user': self.user,
            'action': self.action,
            'target': self.target,
            'detail': self.detail,
            'ip': self.ip,
            'created_at': self.created_at.isoformat() if self.created_at else None
        }