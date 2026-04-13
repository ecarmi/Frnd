"""
Seed the database with realistic Chicago test data.

Usage:
    cd backend
    python -m scripts.seed
"""
import asyncio
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from datetime import datetime, timedelta, timezone
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

from app.models import (
    Base, User, Venue, Event, RSVP, Friendship, TasteProfile,
    EventCategoryEnum, RSVPStatusEnum, FriendshipTierEnum,
    Group, GroupMembership, GroupRoleEnum,
    ActivityPost, ActivityTypeEnum,
)
from app.auth import create_access_token

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://frnd:password@localhost:5432/frnd_db")

engine = create_async_engine(DATABASE_URL, echo=False)
AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def seed():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with AsyncSessionLocal() as db:
        # ----------------------------------------------------------------
        # Test user (you)
        # ----------------------------------------------------------------
        me = User(
            id="test-user-001",
            phone="+15550001234",
            name="Eric",
            latitude=41.7991,
            longitude=-87.5876,
            onboarding_complete=True,
        )
        db.add(me)

        taste = TasteProfile(
            user_id="test-user-001",
            category_affinities={"music": 0.9, "nightlife": 0.7, "food_drink": 0.6, "arts": 0.5},
            genre_weights={"jazz": 0.8, "electronic": 0.7, "hip_hop": 0.6},
            price_sensitivity=0.4,
            time_preferences={"friday_night": 0.9, "saturday_night": 0.95, "sunday_afternoon": 0.5},
            human_readable_summary="You lean toward: live music, late-night venues, $15–$35 range",
        )
        db.add(taste)

        # Friend users
        friends_data = [
            ("user-002", "Alex Chen", 41.7950, -87.5900),
            ("user-003", "Jordan Kim", 41.8020, -87.5850),
            ("user-004", "Sam Rivera", 41.7970, -87.5920),
            ("user-005", "Maya Johnson", 41.8010, -87.5870),
            ("user-006", "Tyler Brooks", 41.7940, -87.5880),
        ]
        for uid, fname, lat, lng in friends_data:
            u = User(id=uid, phone=f"+1555000{uid[-3:]}", name=fname,
                     latitude=lat, longitude=lng, onboarding_complete=True)
            db.add(u)
            db.add(TasteProfile(user_id=uid, category_affinities={"music": 0.7}, genre_weights={}))

        await db.flush()

        # Friendships
        for uid, *_ in friends_data[:3]:
            db.add(Friendship(user_a_id="test-user-001", user_b_id=uid,
                              tier=FriendshipTierEnum.inner_circle))
        for uid, *_ in friends_data[3:]:
            db.add(Friendship(user_a_id="test-user-001", user_b_id=uid,
                              tier=FriendshipTierEnum.friend))

        # ----------------------------------------------------------------
        # Venues
        # ----------------------------------------------------------------
        venues = [
            Venue(id="venue-001", name="The Promontory", latitude=41.7999, longitude=-87.5882,
                  address="5311 S Lake Park Ave, Chicago, IL 60615",
                  vibe_tags=["Intimate", "Live Music", "Craft Cocktails", "Hyde Park"]),
            Venue(id="venue-002", name="Smart Bar", latitude=41.9478, longitude=-87.6538,
                  address="3730 N Clark St, Chicago, IL 60613",
                  vibe_tags=["Late Night", "Dance", "Electronic", "Wrigleyville"]),
            Venue(id="venue-003", name="Hyde Park Art Center", latitude=41.8014, longitude=-87.5979,
                  address="5020 S Cornell Ave, Chicago, IL 60615",
                  vibe_tags=["Artsy", "Community", "Hyde Park"]),
            Venue(id="venue-004", name="Avec", latitude=41.8848, longitude=-87.6500,
                  address="615 W Randolph St, Chicago, IL 60661",
                  vibe_tags=["Brunch", "Lively", "West Loop", "Mediterranean"]),
            Venue(id="venue-005", name="Regenstein Library", latitude=41.7923, longitude=-87.5997,
                  address="1100 E 57th St, Chicago, IL 60637",
                  vibe_tags=["Quiet", "Study", "UChicago"]),
            Venue(id="venue-006", name="Wintrust Arena", latitude=41.8756, longitude=-87.6742,
                  address="200 E Cermak Rd, Chicago, IL 60616",
                  vibe_tags=["Sports", "Large Venue", "South Loop"]),
            Venue(id="venue-007", name="Logan Square Auditorium", latitude=41.9217, longitude=-87.7043,
                  address="2539 N Kedzie Blvd, Chicago, IL 60647",
                  vibe_tags=["Music Venue", "Logan Square", "Indie"]),
            Venue(id="venue-008", name="Millennium Park", latitude=41.8826, longitude=-87.6226,
                  address="201 E Randolph St, Chicago, IL 60602",
                  vibe_tags=["Outdoor", "Free Events", "The Loop"]),
        ]
        for v in venues:
            db.add(v)

        await db.flush()

        # ----------------------------------------------------------------
        # Events (covering tonight + this week)
        # ----------------------------------------------------------------
        now = datetime.now(timezone.utc)

        def dt(days=0, hour=20):
            return now + timedelta(days=days, hours=hour - now.hour)

        events = [
            Event(id="evt-001", title="Jazz at The Promontory",
                  description="An intimate evening of live jazz featuring the Marcus Miller Quartet. Known for their electric blend of soul and bebop.",
                  venue_id="venue-001", start_time=dt(0, 20), end_time=dt(0, 23),
                  price_min=15, price_max=25, category=EventCategoryEnum.music,
                  tags=["Jazz", "Live Music", "Hyde Park", "Intimate"],
                  trending_score=0.87, source="organic"),

            Event(id="evt-002", title="Neon Dreams: Electronic Night",
                  description="Three floors, six DJs. Techno, house, and bass music from local and international acts.",
                  venue_id="venue-002", start_time=dt(0, 22), end_time=dt(1, 4),
                  price_min=20, price_max=30, category=EventCategoryEnum.nightlife,
                  tags=["Electronic", "Techno", "Late Night", "Dance"],
                  trending_score=0.92, source="organic"),

            Event(id="evt-003", title="Hyde Park Art Walk",
                  description="Self-guided tour through 20+ local galleries. Free wine, live demos, artist talks.",
                  venue_id="venue-003", start_time=dt(1, 18), end_time=dt(1, 21),
                  price_min=0, category=EventCategoryEnum.arts,
                  tags=["Art", "Free", "Hyde Park", "Social", "Gallery"],
                  trending_score=0.75, source="aggregated"),

            Event(id="evt-004", title="Sunday Bottomless Brunch",
                  description="2-hour bottomless mimosas and bloody marys with full brunch menu. Live DJ from noon.",
                  venue_id="venue-004", start_time=dt(2, 11), end_time=dt(2, 15),
                  price_min=35, category=EventCategoryEnum.food_drink,
                  tags=["Brunch", "Bottomless", "West Loop", "Social"],
                  trending_score=0.68, source="organic"),

            Event(id="evt-005", title="Study Grind: Finals Week",
                  description="Organized group study session at the Reg. Quiet floors, study groups welcome. Coffee runs at 10pm.",
                  venue_id="venue-005", start_time=dt(0, 18), end_time=dt(0, 23),
                  price_min=0, category=EventCategoryEnum.other,
                  tags=["Study", "UChicago", "Finals", "Academic"],
                  trending_score=0.55, source="organic"),

            Event(id="evt-006", title="Chicago Bulls vs. Celtics",
                  description="Regular season game. Section 108 student tickets available through the Box Office.",
                  venue_id="venue-006", start_time=dt(1, 19), end_time=dt(1, 22),
                  price_min=25, price_max=120, category=EventCategoryEnum.sports,
                  tags=["Basketball", "NBA", "Bulls", "Sports"],
                  trending_score=0.95, source="aggregated"),

            Event(id="evt-007", title="Indie Night: Local Bands Showcase",
                  description="Four local indie/folk bands. 21+. Bar opens at 7, doors at 8.",
                  venue_id="venue-007", start_time=dt(1, 20), end_time=dt(2, 0),
                  price_min=12, category=EventCategoryEnum.music,
                  tags=["Indie", "Folk", "Live Music", "Logan Square"],
                  trending_score=0.72, source="organic"),

            Event(id="evt-008", title="Free Concert: Grant Park Orchestra",
                  description="Free outdoor classical concert at Millennium Park. Bring a blanket.",
                  venue_id="venue-008", start_time=dt(2, 19), end_time=dt(2, 21),
                  price_min=0, category=EventCategoryEnum.music,
                  tags=["Classical", "Free", "Outdoor", "The Loop"],
                  trending_score=0.80, source="aggregated"),
        ]
        for e in events:
            db.add(e)

        await db.flush()

        # RSVPs from friends
        rsvps = [
            ("user-002", "evt-001", RSVPStatusEnum.going),
            ("user-003", "evt-001", RSVPStatusEnum.going),
            ("user-004", "evt-002", RSVPStatusEnum.going),
            ("user-002", "evt-004", RSVPStatusEnum.interested),
            ("user-005", "evt-004", RSVPStatusEnum.going),
            ("user-006", "evt-004", RSVPStatusEnum.going),
            ("user-003", "evt-006", RSVPStatusEnum.interested),
        ]
        for uid, eid, status in rsvps:
            db.add(RSVP(user_id=uid, event_id=eid, status=status))

        # ----------------------------------------------------------------
        # Groups
        # ----------------------------------------------------------------
        group1 = Group(
            id="group-001",
            name="UChicago CS '26",
            description="For CS students graduating in 2026. Private events and study sessions.",
            creator_id="test-user-001",
            is_private=True,
        )
        db.add(group1)
        await db.flush()

        for uid in ["test-user-001", "user-002", "user-003"]:
            role = GroupRoleEnum.owner if uid == "test-user-001" else GroupRoleEnum.member
            db.add(GroupMembership(group_id="group-001", user_id=uid, role=role))

        # ----------------------------------------------------------------
        # Activity Posts (LFG)
        # ----------------------------------------------------------------
        posts = [
            ActivityPost(
                id="act-001",
                creator_id="user-002",
                title="Homework grind at Reg tonight",
                description="Working on 213 pset, happy to help others too. Floor 3.",
                activity_type=ActivityTypeEnum.study,
                location="Regenstein Library, Floor 3",
                scheduled_time=dt(0, 19),
                max_participants=5,
            ),
            ActivityPost(
                id="act-002",
                creator_id="user-004",
                title="Pickup basketball at Ratner",
                description="3v3 or 5v5 depending on who shows. All skill levels.",
                activity_type=ActivityTypeEnum.sports,
                location="Ratner Athletic Center",
                scheduled_time=dt(1, 17),
                max_participants=10,
            ),
        ]
        for p in posts:
            db.add(p)

        await db.commit()

        token = create_access_token("test-user-001")
        print("\n✅ Seed complete!")
        print(f"\n📱 Test user token (paste into APIService.swift for dev):\n   {token}\n")
        print("Or use the dev bypass: phone=anything, code=000000\n")


if __name__ == "__main__":
    asyncio.run(seed())
