from django.urls import path

from . import views

urlpatterns = [
    path('health/', views.HealthView.as_view(), name='health'),
    path('context/', views.ContextView.as_view(), name='context'),
    path('me/roles/', views.MyRolesView.as_view(), name='my-roles'),
    path('search/', views.SearchView.as_view(), name='search'),
    path('manage/summary/', views.ManageSummaryView.as_view(), name='manage-summary'),
]
