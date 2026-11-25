from django.urls import path
from rest_framework.routers import DefaultRouter

from . import guard_views, views

router = DefaultRouter()
router.register('visitors', views.VisitorViewSet, basename='visitor')
router.register('frequent-entries', views.FrequentEntryViewSet, basename='frequent-entry')
router.register('kid-exits', views.KidExitViewSet, basename='kid-exit')
router.register('sos', views.SOSViewSet, basename='sos')
router.register('guard/visitors', views.GuardVisitorViewSet, basename='guard-visitor')
router.register('guard/daily-help', views.GuardDailyHelpViewSet, basename='guard-daily-help')
router.register('guard/kid-exits', views.GuardKidExitViewSet, basename='guard-kid-exit')
router.register('guard/sos', views.GuardSOSViewSet, basename='guard-sos')
router.register('manage/visitor-log', views.ManageVisitorLogViewSet, basename='manage-visitor-log')
router.register('manage/sos', views.ManageSOSViewSet, basename='manage-sos')
router.register('guard/shifts', guard_views.GuardShiftViewSet, basename='guard-shift')
router.register('guard/vehicles', guard_views.GuardVehicleViewSet, basename='guard-vehicle')
router.register('guard/staff', guard_views.GuardStaffViewSet, basename='guard-staff')
router.register('guard/incidents', guard_views.GuardIncidentViewSet, basename='guard-incident')
router.register('guard/gates', guard_views.GuardGateViewSet, basename='guard-gate')
router.register('manage/incidents', guard_views.ManageIncidentViewSet, basename='manage-incident')

urlpatterns = [
    path('guard/context/', guard_views.GuardContextView.as_view(), name='guard-context'),
    path('guard/summary/', guard_views.GuardSummaryView.as_view(), name='guard-summary'),
    path('guard/directory/', guard_views.GuardDirectoryView.as_view(), name='guard-directory'),
    *router.urls,
]
