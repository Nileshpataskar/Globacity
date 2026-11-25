from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register('platform/communities', views.PlatformCommunityViewSet, basename='platform-community')
router.register('manage/communities', views.ManageCommunityViewSet, basename='manage-community')
router.register('manage/towers', views.ManageTowerViewSet, basename='manage-tower')
router.register('manage/units', views.ManageUnitViewSet, basename='manage-unit')
router.register('manage/gates', views.ManageGateViewSet, basename='manage-gate')
router.register('manage/memberships', views.ManageMembershipViewSet, basename='manage-membership')
router.register('manage/staff', views.ManageStaffViewSet, basename='manage-staff')
router.register('manage/emergency-contacts', views.ManageEmergencyContactViewSet, basename='manage-emergency-contact')
router.register('communities', views.CommunityBrowseViewSet, basename='community')
router.register('me/units', views.MyUnitsViewSet, basename='my-unit')
router.register('emergency-contacts', views.EmergencyContactsViewSet, basename='emergency-contact')

urlpatterns = [
    path('directory/residents/', views.ResidentDirectoryView.as_view(), name='directory-residents'),
    path('directory/staff/', views.StaffDirectoryView.as_view(), name='directory-staff'),
    *router.urls,
]
