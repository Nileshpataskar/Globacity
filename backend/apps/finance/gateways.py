"""Payment gateways, selected per country (``Country.payment_gateway``).

``mock`` is free and completes payments through ``/finance/payments/{id}/mock-confirm/``.
To go live with Noqodi (or Razorpay/Stripe for other countries), implement the class below and
set the country's gateway in the platform admin. Nothing else in the app changes.
"""

from django.urls import reverse


class GatewayNotConfigured(Exception):
    pass


class BaseGateway:
    code = ''

    def create_checkout(self, payment, request) -> dict:
        """Return what the app needs to complete payment (redirect URL, SDK token, ...)."""
        raise NotImplementedError

    def parse_webhook(self, request):
        """Return ``(our_reference, success: bool, gateway_reference, raw_payload)``."""
        raise NotImplementedError


class MockGateway(BaseGateway):
    code = 'mock'

    def create_checkout(self, payment, request):
        url = request.build_absolute_uri(reverse('payment-mock-confirm', args=[payment.pk]))
        return {
            'gateway': self.code,
            'confirm_url': url,
            'instructions': 'Development gateway: POST {"success": true} to confirm_url to complete the payment.',
        }

    def parse_webhook(self, request):
        data = request.data
        return data.get('reference'), bool(data.get('success')), data.get('gateway_reference', ''), dict(data)


class NoqodiGateway(BaseGateway):
    """UAE. Needs merchant credentials from Noqodi; implement their session + callback APIs here."""

    code = 'noqodi'

    def create_checkout(self, payment, request):
        raise GatewayNotConfigured('Noqodi is not configured yet. Use the mock gateway for development.')

    def parse_webhook(self, request):
        raise GatewayNotConfigured('Noqodi is not configured yet.')


_GATEWAYS = {g.code: g for g in (MockGateway, NoqodiGateway)}


def get_gateway(code):
    cls = _GATEWAYS.get(code)
    if cls is None:
        raise GatewayNotConfigured(f'Payment gateway "{code}" is not available.')
    return cls()
