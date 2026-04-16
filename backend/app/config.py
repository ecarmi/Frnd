from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql+asyncpg://frnd:password@localhost:5432/frnd_db"
    redis_url: str = "redis://localhost:6379/0"
    secret_key: str = "dev-secret-change-in-production"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 10080  # 7 days

    resend_api_key: str = ""
    resend_from_email: str = "Frnd <onboarding@resend.dev>"

    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_phone_number: str = ""

    environment: str = "development"
    default_feed_lat: float = 41.7991
    default_feed_lng: float = -87.5876
    default_trending_label: str = "Trending nearby"
    launch_access_message: str = "Frnd is currently available for approved campus email domains. More universities are coming soon!"
    allowed_email_domains: str = "uchicago.edu"

    class Config:
        env_file = ".env"


settings = Settings()
