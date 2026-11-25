from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser


@database_sync_to_async
def _user_from_token(token):
    from rest_framework_simplejwt.exceptions import TokenError
    from rest_framework_simplejwt.tokens import AccessToken

    from apps.accounts.models import User

    try:
        user_id = AccessToken(token)['user_id']
        return User.objects.get(pk=user_id, is_active=True)
    except (TokenError, KeyError, User.DoesNotExist):
        return AnonymousUser()


class JWTQueryAuthMiddleware:
    """Authenticates WebSocket connections with ``?token=<JWT access token>``."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        token = parse_qs(scope.get('query_string', b'').decode()).get('token', [None])[0]
        scope['user'] = await _user_from_token(token) if token else AnonymousUser()
        return await self.app(scope, receive, send)
