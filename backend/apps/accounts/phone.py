import re

from rest_framework.exceptions import ValidationError

from apps.locations.models import Country


def normalize_phone(raw: str):
    """Return ``(e164_phone, country)``. Validates the dialing code and length against active countries."""
    phone = re.sub(r'[\s\-()]', '', raw or '')
    if phone.startswith('00'):
        phone = '+' + phone[2:]
    if not re.fullmatch(r'\+\d{7,15}', phone):
        raise ValidationError({'phone': 'Use international format, e.g. +971501234567.'})

    countries = sorted(Country.objects.filter(is_active=True), key=lambda c: len(c.phone_code), reverse=True)
    for country in countries:
        if phone.startswith(country.phone_code):
            national = phone[len(country.phone_code):]
            if len(national) != country.phone_number_length:
                raise ValidationError(
                    {'phone': f'{country.name} numbers must have {country.phone_number_length} digits after '
                              f'{country.phone_code}.'}
                )
            return phone, country
    raise ValidationError({'phone': 'This country is not supported yet.'})
