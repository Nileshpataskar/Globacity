from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register('helpdesk/categories', views.TicketCategoryViewSet, basename='ticket-category')
router.register('helpdesk/tickets', views.TicketViewSet, basename='ticket')
router.register('manage/ticket-categories', views.ManageTicketCategoryViewSet, basename='manage-ticket-category')
router.register('manage/tickets', views.ManageTicketViewSet, basename='manage-ticket')

urlpatterns = router.urls
