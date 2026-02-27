import io
import os
from datetime import datetime
from minio import Minio
from minio.error import S3Error
from flask import current_app

class MinIOService:
    _instance = None
    _client = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    def init_app(self, app):
        try:
            self._client = Minio(
                app.config['MINIO_ENDPOINT'],
                access_key=app.config['MINIO_ACCESS_KEY'],
                secret_key=app.config['MINIO_SECRET_KEY'],
                secure=app.config['MINIO_SECURE']
            )
            self._bucket = app.config['MINIO_BUCKET']
            self._ensure_bucket()
        except Exception as e:
            app.logger.error(f"MinIO initialization failed: {e}")
            self._client = None
    
    def _ensure_bucket(self):
        if self._client:
            try:
                if not self._client.bucket_exists(self._bucket):
                    self._client.make_bucket(self._bucket)
            except S3Error as e:
                current_app.logger.error(f"Failed to create bucket: {e}")
    
    def upload_report(self, file_content, filename, content_type='text/html'):
        if not self._client:
            return None, None
        
        try:
            date_prefix = datetime.now().strftime('%Y/%m/%d')
            object_name = f"reports/{date_prefix}/{filename}"
            
            if isinstance(file_content, str):
                file_content = file_content.encode('utf-8')
            
            self._client.put_object(
                self._bucket,
                object_name,
                io.BytesIO(file_content),
                len(file_content),
                content_type=content_type
            )
            
            url = self._client.presigned_get_object(self._bucket, object_name)
            
            return object_name, url
        except S3Error as e:
            current_app.logger.error(f"Failed to upload report: {e}")
            return None, None
    
    def get_report(self, object_name):
        if not self._client:
            return None

        response = None
        try:
            response = self._client.get_object(self._bucket, object_name)
            return response.read()
        except S3Error as e:
            current_app.logger.error(f"Failed to get report: {e}")
            return None
        finally:
            if response is not None:
                response.close()
                response.release_conn()
    
    def get_report_url(self, object_name, expires=3600):
        if not self._client:
            return None
        
        try:
            from datetime import timedelta
            url = self._client.presigned_get_object(
                self._bucket, 
                object_name,
                expires=timedelta(seconds=expires)
            )
            return url
        except S3Error as e:
            current_app.logger.error(f"Failed to get report URL: {e}")
            return None
    
    def delete_report(self, object_name):
        if not self._client:
            return False
        
        try:
            self._client.remove_object(self._bucket, object_name)
            return True
        except S3Error as e:
            current_app.logger.error(f"Failed to delete report: {e}")
            return False
    
    def list_reports(self, prefix='reports/'):
        if not self._client:
            return []
        
        try:
            objects = self._client.list_objects(self._bucket, prefix=prefix, recursive=True)
            return [obj.object_name for obj in objects]
        except S3Error as e:
            current_app.logger.error(f"Failed to list reports: {e}")
            return []

minio_service = MinIOService()
