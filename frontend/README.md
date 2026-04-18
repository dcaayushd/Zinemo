# 🎬 Zinemo — Full-Stack Movie & TV Logger

A beautifully crafted Flutter mobile app paired with a powerful AI/ML recommendation engine to discover, log, and rate movies and TV shows.

### ✨ Features

- **Smart Recommendations**: Hybrid ML recommendation engine using LightFM, ALS, and semantic embeddings
- **Intuitive Logging**: Quick-log workflow with ratings, reviews, and watchlist management
- **Gorgeous UI**: Dark-first cinema aesthetic with smooth animations and glassmorphism effects
- **Social Features**: Follow friends, share lists, and see what others are watching
- **Discovery**: Trending content, personalized feeds, and advanced search
- **Wrapped Stats**: Annual viewing statistics with heatmaps and charts
- **Offline Support**: Hive-cached logs and watchlist for offline access

### 🛠️ Tech Stack

**Frontend**
- Flutter 3.x with Dart
- Riverpod 2.x for state management
- GoRouter for navigation
- Supabase for real-time authentication and database
- Dio for HTTP with retry logic and interceptors

**Backend**
- Node.js 20+ with TypeScript and Express.js
- PostgreSQL (Supabase) with pgvector for semantic search
- BullMQ + Redis for job queue and auto-retraining

**ML Microservice**
- Python FastAPI with LightFM, ALS, and Sentence-Transformers
- Collaborative + content-based hybrid recommendations
- Cold-start handling for new users
- Automatic retraining every 6 hours

**Integrations**
- TMDB API (movies, TV, trailers)
- OMDB API (IMDb ratings)
- YouTube Data API (trailer search)
- Recombee (optional behavioral recommendations)

### 🚀 Getting Started

#### Prerequisites
- Flutter 3.x
- Node.js 20+
- Python 3.11+
- PostgreSQL (via Supabase)

#### Flutter Setup
```bash
cd frontend
flutter pub get
flutter run
```

### 📱 Core Workflows

**Discovery & Logging**
1. Browse trending or personalized recommendations
2. Tap a poster → full detail screen with trailers
3. Swipe up to log → rate, add review, mark as watched

**Recommendations Screen**
- Vertical PageView of full-screen movie cards
- Background color morphs to dominant poster color
- Genre selector pill with slot-machine animation
- "Because you liked X" reason explanations

**Onboarding**
- Select favorite genres for cold-start seeding
- Rate 10 popular movies to initialize recommendations
- Preferences stored immediately for instant personalization

### 🧠 Recommendation Engine

**Mode A: From-Scratch ML (default)**
- LightFM hybrid matrix factorization (WARP loss)
- ALS collaborative filtering for backup
- Content-based similarity via TF-IDF and embeddings
- Adaptive weighting based on user activity tier

**Mode B: Recombee + pgvector Hybrid**
- Recombee real-time behavioral signals
- PostgreSQL pgvector cosine similarity search
- TMDB trending fallback

Switch modes via `RECOMMENDATION_MODE` environment variable.

### 🎨 Design Highlights

- **Dark-first cinema aesthetic**: near-black backgrounds, red and gold accents
- **Smooth micro-animations**: fade, scale, slide, blur transitions
- **Responsive layouts**: works on phones and tablets
- **Glassmorphism effects**: frosted overlays, backdrop blur
- **Custom shimmer skeletons**: loading states

### 🔐 Security

- Supabase Row Level Security on all tables
- JWT token verification via Supabase Auth
- Rate limiting on API endpoints
- Secure storage for tokens with `flutter_secure_storage`
- Never log sensitive data

### 📦 Deployment

**Render.com** (3 services)
- Node.js API (free tier)
- Python ML service (free tier with Docker)
- Redis queue (free tier)

**Supabase** (free tier)
- PostgreSQL database
- Authentication (Google, Apple, email)
- Row-level security policies
- pgvector embeddings

**GitHub Actions** CI/CD pipeline for automated testing and deployment.

### 📚 Project Structure

```
zinemo/
├── frontend/               # Flutter app
│   ├── lib/
│   │   ├── core/          # Theme, constants, utilities
│   │   ├── features/      # Feature modules (auth, home, detail, etc.)
│   │   ├── providers/     # Riverpod state management
│   │   └── main.dart
│   └── pubspec.yaml
│
├── backend/               # Node.js API
│   ├── src/
│   │   ├── routes/        # REST endpoints
│   │   ├── services/      # Business logic
│   │   ├── middleware/    # Auth, logging, error handling
│   │   └── app.ts
│   └── package.json
│
└── ml_service/            # Python ML microservice
    ├── app/
    │   ├── models/        # LightFM, ALS, content-based
    │   ├── training/      # Training pipeline and scheduler
    │   ├── inference/     # Recommender and explainer
    │   └── main.py
    └── requirements.txt
```

### 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### 📄 License

This project is licensed under the MIT License — see LICENSE file for details.

### 👥 Authors

Built with ❤️ by dcaayushd.

---

**Status**: Active Development | **Latest Release**: 1.0.0-beta
