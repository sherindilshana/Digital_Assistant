from django.contrib import admin
from django.urls import path
from assistant.views import TranslationView, FormAssistView, UniversalScanView  # <--- NEW: Import FormAssistView

urlpatterns = [
    path('admin/', admin.site.urls),
    
    # Existing Translation Endpoint
    path('api/translate/', TranslationView.as_view(), name='translate'),
    
    # NEW: Form Assistance Endpoint
    path('api/form-assist/', FormAssistView.as_view(), name='form_assist'),

    # Add this inside urlpatterns in urls.py
    path('api/universal-scan/', UniversalScanView.as_view(), name='universal_scan'),
]