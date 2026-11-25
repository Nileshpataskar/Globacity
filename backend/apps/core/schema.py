from drf_spectacular.openapi import AutoSchema
from drf_spectacular.utils import OpenApiParameter

UNIT_HEADER_PARAM = OpenApiParameter(
    name='X-Unit-ID',
    type=str,
    location=OpenApiParameter.HEADER,
    required=False,
    description='Unit to act on (from /api/v1/me/units/). Optional if you belong to exactly one unit.',
)

_AREA_TITLES = {'platform': 'Platform', 'manage': 'Manage', 'guard': 'Guard'}


class AppAutoSchema(AutoSchema):
    """Adds the X-Unit-ID header to resident endpoints and groups Swagger tags by area."""

    def get_override_parameters(self):
        params = super().get_override_parameters()
        if getattr(self.view, 'unit_scoped', False):
            params = [*params, UNIT_HEADER_PARAM]
        return params

    def get_tags(self):
        parts = [p for p in self.path.replace('/api/v1/', '', 1).split('/') if p and not p.startswith('{')]
        if not parts:
            return ['General']
        if parts[0] in _AREA_TITLES and len(parts) > 1:
            return [f'{_AREA_TITLES[parts[0]]} · {parts[1].replace("-", " ")}']
        return [parts[0].replace('-', ' ').title()]
