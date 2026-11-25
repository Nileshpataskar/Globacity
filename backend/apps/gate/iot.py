"""IoT gate / boom-barrier drivers. The mock driver is free and logs the command.

To connect real hardware (e.g. a relay controller or vendor cloud API), subclass ``BaseGateDriver``
and set ``IOT_GATE_DRIVER`` in .env to its dotted path.
"""

import logging

from django.conf import settings
from django.utils.module_loading import import_string

logger = logging.getLogger('apps.iot')


class BaseGateDriver:
    def open(self, gate) -> tuple[bool, str]:
        raise NotImplementedError


class MockGateDriver(BaseGateDriver):
    def open(self, gate):
        logger.info('[IoT] open gate %s (device %s)', gate.name, gate.iot_device_id or '-')
        return True, 'Gate opened (simulated)'


def open_gate(gate):
    driver = import_string(getattr(settings, 'IOT_GATE_DRIVER', 'apps.gate.iot.MockGateDriver'))()
    return driver.open(gate)
