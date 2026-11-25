from datetime import date

from django.db.models import Avg, Count, Exists, Max, OuterRef, Prefetch
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response

from apps.core.scoping import UnitScopedViewSet
from apps.core.utils import community_today, generate_code

from .models import DailyHelp, DailyHelpAssignment, DailyHelpAttendance, DailyHelpReview, FamilyMember, Pet, Vehicle
from .serializers import (
    AttendanceMonthSerializer,
    DailyHelpReviewSerializer,
    DailyHelpSerializer,
    FamilyMemberSerializer,
    PetSerializer,
    VehicleSerializer,
)


class FamilyMemberViewSet(UnitScopedViewSet):
    serializer_class = FamilyMemberSerializer
    queryset = FamilyMember.objects.all()
    filterset_fields = ['is_minor']


class VehicleViewSet(UnitScopedViewSet):
    serializer_class = VehicleSerializer
    queryset = Vehicle.objects.all()


class PetViewSet(UnitScopedViewSet):
    serializer_class = PetSerializer
    queryset = Pet.objects.all()


def helpers_queryset():
    open_visit = DailyHelpAttendance.objects.filter(helper=OuterRef('pk'), check_out__isnull=True)
    return DailyHelp.objects.annotate(
        rating=Avg('reviews__rating'),
        reviews_count=Count('reviews', distinct=True),
        homes_served=Count('assignments', distinct=True),
        is_inside=Exists(open_visit),
        last_entry=Max('attendance__check_in'),
    )


class DailyHelpViewSet(UnitScopedViewSet):
    """Daily help working for your unit. Adding someone who already works in the community links them."""

    serializer_class = DailyHelpSerializer
    queryset = DailyHelp.objects.all()
    scope_lookup = 'assignments__unit'
    search_fields = ['name', 'role']
    http_method_names = ['get', 'post', 'patch', 'delete']

    def get_queryset(self):
        qs = helpers_queryset()
        if getattr(self, 'swagger_fake_view', False):
            return qs.none()
        return qs.filter(assignments__unit=self.unit).prefetch_related(
            Prefetch('assignments', queryset=DailyHelpAssignment.objects.filter(unit=self.unit),
                     to_attr='my_assignments')
        )

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        if not getattr(self, 'swagger_fake_view', False) and self.request.user.is_authenticated:
            ctx['unit'] = self.unit
        return ctx

    def perform_create(self, serializer):
        data = serializer.validated_data
        timing = data.pop('timing', '')
        community = self.community
        helper = DailyHelp.objects.filter(community=community, phone=data['phone']).first()
        if helper is None:
            code = generate_code(lambda c: DailyHelp.objects.filter(community=community, pass_code=c).exists())
            helper = serializer.save(community=community, pass_code=code)
        DailyHelpAssignment.objects.update_or_create(
            helper=helper, unit=self.unit, defaults={'timing': timing, 'added_by': self.request.user}
        )
        serializer.instance = helper

    def create(self, request, *args, **kwargs):
        s = self.get_serializer(data=request.data)
        s.is_valid(raise_exception=True)
        self.perform_create(s)
        helper = self.get_queryset().get(pk=s.instance.pk)
        return Response(self.get_serializer(helper).data, status=status.HTTP_201_CREATED)

    def perform_update(self, serializer):
        timing = serializer.validated_data.pop('timing', None)
        serializer.save()
        if timing is not None:
            DailyHelpAssignment.objects.filter(helper=serializer.instance, unit=self.unit).update(timing=timing)

    def perform_destroy(self, instance):
        """Removes the helper from your unit only."""
        DailyHelpAssignment.objects.filter(helper=instance, unit=self.unit).delete()

    @extend_schema(parameters=[OpenApiParameter('month', str, description='YYYY-MM, defaults to this month')],
                   responses=AttendanceMonthSerializer)
    @action(detail=True, methods=['get'])
    def attendance(self, request, pk=None):
        helper = self.get_object()
        month = request.query_params.get('month')
        try:
            first = date.fromisoformat(f'{month}-01') if month else community_today(self.community).replace(day=1)
        except ValueError:
            raise ValidationError({'month': 'Use YYYY-MM.'})
        nxt = first.replace(year=first.year + 1, month=1) if first.month == 12 else first.replace(month=first.month + 1)
        records = list(helper.attendance.filter(date__gte=first, date__lt=nxt).order_by('date', 'check_in'))
        days = sorted({r.date.day for r in records})
        return Response(AttendanceMonthSerializer({
            'month': first.strftime('%Y-%m'), 'present_days': days, 'days_present': len(days), 'records': records,
        }).data)

    @extend_schema(methods=['get'], responses=DailyHelpReviewSerializer(many=True))
    @extend_schema(methods=['post'], request=DailyHelpReviewSerializer, responses=DailyHelpReviewSerializer,
                   description='Create or update your review of this helper.')
    @action(detail=True, methods=['get', 'post'])
    def reviews(self, request, pk=None):
        helper = self.get_object()
        if request.method == 'GET':
            qs = helper.reviews.select_related('author', 'unit__tower')
            return Response(DailyHelpReviewSerializer(qs, many=True).data)
        s = DailyHelpReviewSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        review, _ = DailyHelpReview.objects.update_or_create(
            helper=helper, author=request.user, defaults={**s.validated_data, 'unit': self.unit}
        )
        return Response(DailyHelpReviewSerializer(review).data, status=status.HTTP_201_CREATED)
