from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register('notices', views.NoticeViewSet, basename='notice')
router.register('polls', views.PollViewSet, basename='poll')
router.register('events', views.EventViewSet, basename='event')
router.register('forum/posts', views.ForumPostViewSet, basename='forum-post')
router.register('classifieds', views.ClassifiedViewSet, basename='classified')
router.register('services/vendors', views.VendorViewSet, basename='vendor')
router.register('services/bookings', views.BookingViewSet, basename='booking')
router.register('move-requests', views.MoveRequestViewSet, basename='move-request')
router.register('manage/notices', views.ManageNoticeViewSet, basename='manage-notice')
router.register('manage/polls', views.ManagePollViewSet, basename='manage-poll')
router.register('manage/events', views.ManageEventViewSet, basename='manage-event')
router.register('manage/vendors', views.ManageVendorViewSet, basename='manage-vendor')
router.register('manage/bookings', views.ManageBookingViewSet, basename='manage-booking')
router.register('manage/move-requests', views.ManageMoveRequestViewSet, basename='manage-move-request')
router.register('manage/forum', views.ManageForumViewSet, basename='manage-forum')
router.register('manage/classifieds', views.ManageClassifiedViewSet, basename='manage-classified')

urlpatterns = router.urls
