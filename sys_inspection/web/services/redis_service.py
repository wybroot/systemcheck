import json
from datetime import timedelta
from flask import current_app
from . import redis_client

class RedisService:
    CACHE_PREFIX = 'inspect:'
    
    @staticmethod
    def get(key):
        if not redis_client:
            return None
        try:
            value = redis_client.get(f"{RedisService.CACHE_PREFIX}{key}")
            if value:
                return json.loads(value)
            return None
        except Exception as e:
            current_app.logger.error(f"Redis get error: {e}")
            return None
    
    @staticmethod
    def set(key, value, expire=300):
        if not redis_client:
            return False
        try:
            redis_client.setex(
                f"{RedisService.CACHE_PREFIX}{key}",
                timedelta(seconds=expire),
                json.dumps(value)
            )
            return True
        except Exception as e:
            current_app.logger.error(f"Redis set error: {e}")
            return False
    
    @staticmethod
    def delete(key):
        if not redis_client:
            return False
        try:
            redis_client.delete(f"{RedisService.CACHE_PREFIX}{key}")
            return True
        except Exception as e:
            current_app.logger.error(f"Redis delete error: {e}")
            return False
    
    @staticmethod
    def delete_pattern(pattern):
        if not redis_client:
            return False
        try:
            keys = redis_client.keys(f"{RedisService.CACHE_PREFIX}{pattern}")
            if keys:
                redis_client.delete(*keys)
            return True
        except Exception as e:
            current_app.logger.error(f"Redis delete_pattern error: {e}")
            return False
    
    @staticmethod
    def get_server_cache(server_id):
        return RedisService.get(f"server:{server_id}")
    
    @staticmethod
    def set_server_cache(server_id, data, expire=60):
        return RedisService.set(f"server:{server_id}", data, expire)
    
    @staticmethod
    def get_dashboard_cache():
        return RedisService.get("dashboard")
    
    @staticmethod
    def set_dashboard_cache(data, expire=30):
        return RedisService.set("dashboard", data, expire)
    
    @staticmethod
    def get_inspection_cache(inspection_id):
        return RedisService.get(f"inspection:{inspection_id}")
    
    @staticmethod
    def set_inspection_cache(inspection_id, data, expire=300):
        return RedisService.set(f"inspection:{inspection_id}", data, expire)
    
    @staticmethod
    def clear_all_cache():
        return RedisService.delete_pattern("*")