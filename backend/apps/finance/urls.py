from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register('finance/invoices', views.InvoiceViewSet, basename='invoice')
router.register('finance/payments', views.PaymentViewSet, basename='payment')
router.register('manage/charge-types', views.ManageChargeTypeViewSet, basename='manage-charge-type')
router.register('manage/invoices', views.ManageInvoiceViewSet, basename='manage-invoice')
router.register('manage/payments', views.ManagePaymentViewSet, basename='manage-payment')
router.register('manage/defaulters', views.ManageDefaulterViewSet, basename='manage-defaulter')

urlpatterns = [
    path('finance/webhooks/<str:gateway>/', views.PaymentWebhookView.as_view(), name='payment-webhook'),
    *router.urls,
]
