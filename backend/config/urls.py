from django.contrib import admin
from django.urls import path
from assistant.views import TranslationView  # Import your view

urlpatterns = [
    path('admin/', admin.site.urls),
    
    # The API Endpoint
    path('api/translate/', TranslationView.as_view(), name='translate'),
]