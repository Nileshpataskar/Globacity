"""SMS backends. The console backend is free and used by default.

To use a real provider, subclass ``BaseSMSBackend`` and set ``SMS_BACKEND`` in .env.
"""

import logging

from django.conf import settings
from django.utils.module_loading import import_string

logger = logging.getLogger('apps.sms')


class BaseSMSBackend:
    def send(self, phone: str, message: str) -> None:
        raise NotImplementedError


class ConsoleSMSBackend(BaseSMSBackend):
    def send(self, phone, message):
        logger.info('[SMS to %s] %s', phone, message)


def send_sms(phone: str, message: str) -> None:
    import_string(settings.SMS_BACKEND)().send(phone, message)
