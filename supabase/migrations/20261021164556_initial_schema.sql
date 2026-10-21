-- =========================================================
-- 1. TIPOS ENUMERADOS (Para estandarizar datos y ahorrar espacio)
-- =========================================================
CREATE TYPE public.user_role AS ENUM ('socio', 'admin', 'gestor_contenido');
CREATE TYPE public.post_type AS ENUM ('text', 'image', 'video', 'referral', 'challenge_completed', 'badge_earned', 'campaign_news');
CREATE TYPE public.media_type AS ENUM ('image', 'video', 'gif');
CREATE TYPE public.reaction_type AS ENUM ('like', 'love', 'haha', 'wow', 'sad', 'angry');
CREATE TYPE public.referral_status AS ENUM ('pending', 'registered', 'active_client');
CREATE TYPE public.activity_type AS ENUM ('challenge', 'training', 'workshop', 'financial_game', 'health_wellness');
CREATE TYPE public.activity_category AS ENUM ('financial_education', 'health_wellness', 'general');
CREATE TYPE public.activity_status AS ENUM ('enrolled', 'in_progress', 'completed');
CREATE TYPE public.redemption_status AS ENUM ('pending', 'approved', 'delivered', 'cancelled');
CREATE TYPE public.redemption_type AS ENUM ('souvenir', 'monetary_accreditation'); -- RF-06
CREATE TYPE public.credit_intention_status AS ENUM ('pending', 'under_review', 'approved', 'rejected');

-- =========================================================
-- 2. TABLAS PRINCIPALES
-- =========================================================

-- 2.1 Perfiles de Usuario (Extensión de auth.users)
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  role public.user_role DEFAULT 'socio',
  full_name TEXT,
  avatar_url TEXT,
  qr_code_url TEXT, -- RF-01: Código QR único
  province TEXT,    -- RF-03: Para filtrar el feed por provincia
  bio TEXT,
  account_number TEXT,
  total_points INT DEFAULT 0,
  current_level INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.2 Campañas (RF-11)
CREATE TABLE public.campaigns (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.3 Publicaciones (Red Social)
CREATE TABLE public.posts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL, -- RF-11
  content TEXT,
  post_type public.post_type DEFAULT 'text',
  reference_id UUID, -- ID del reto, insignia o referido relacionado
  metadata JSONB DEFAULT '{}',
  likes_count INT DEFAULT 0,
  comments_count INT DEFAULT 0,
  is_published BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.4 Media de Publicaciones (Imágenes/Videos)
CREATE TABLE public.post_media (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE NOT NULL,
  storage_path TEXT NOT NULL, -- Ruta en Supabase Storage
  media_type public.media_type DEFAULT 'image',
  order_index INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.5 Comentarios
CREATE TABLE public.comments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  parent_id UUID REFERENCES public.comments(id) ON DELETE CASCADE, -- Hilos
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.6 Reacciones
CREATE TABLE public.reactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  reaction_type public.reaction_type DEFAULT 'like',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(post_id, user_id, reaction_type)
);

-- 2.7 Seguidores
CREATE TABLE public.follows (
  follower_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (follower_id, following_id)
);

-- 2.8 Referidos
CREATE TABLE public.referrals (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  referrer_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  referred_contact TEXT NOT NULL,
  referred_user_id UUID REFERENCES public.profiles(id),
  referral_code TEXT UNIQUE,
  status public.referral_status DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.9 Intención de Crédito (RF-02)
CREATE TABLE public.credit_intentions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  referral_id UUID REFERENCES public.referrals(id) ON DELETE SET NULL,
  requested_amount NUMERIC,
  product_type TEXT,
  deposit_exemption_applied BOOLEAN DEFAULT FALSE, -- Exención de los $30
  status public.credit_intention_status DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.10 Ledger de Puntos (Auditoría inmutable - RF-04)
CREATE TABLE public.points_ledger (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  amount INT NOT NULL,
  reason TEXT NOT NULL, -- ej: 'referral_success', 'challenge_completed'
  reference_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.11 Insignias
CREATE TABLE public.badges (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  icon_url TEXT,
  criteria JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.user_badges (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  badge_id UUID REFERENCES public.badges(id) ON DELETE CASCADE NOT NULL,
  awarded_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, badge_id)
);

-- 2.12 Recompensas y Canjes (RF-06)
CREATE TABLE public.rewards_catalog (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  points_cost INT NOT NULL,
  redemption_type public.redemption_type NOT NULL, -- souvenir o monetary_accreditation
  stock INT DEFAULT -1, -- -1 = ilimitado
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.reward_redemptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  reward_id UUID REFERENCES public.rewards_catalog(id) ON DELETE CASCADE NOT NULL,
  points_spent INT NOT NULL,
  status public.redemption_status DEFAULT 'pending',
  delivery_notes TEXT, -- Dirección (souvenir) o # cuenta (acreditación)
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.13 Actividades (Capacitaciones, Talleres, Juegos, Retos - RF-05)
CREATE TABLE public.activities (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
  type public.activity_type NOT NULL,
  category public.activity_category DEFAULT 'general',
  title TEXT NOT NULL,
  description TEXT,
  cover_image_url TEXT,
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  points_reward INT DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.activity_progress (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  activity_id UUID REFERENCES public.activities(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  status public.activity_status DEFAULT 'enrolled',
  progress_data JSONB DEFAULT '{}',
  completed_at TIMESTAMPTZ,
  UNIQUE(activity_id, user_id)
);

-- 2.14 Notificaciones (RF-10)
CREATE TABLE public.notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  type TEXT NOT NULL,
  title TEXT,
  message TEXT,
  reference_table TEXT,
  reference_id UUID,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =========================================================
-- 3. ÍNDICES DE RENDIMIENTO (RNF-01: < 2 segundos)
-- =========================================================
CREATE INDEX idx_profiles_province ON public.profiles(province);
CREATE INDEX idx_posts_user_created ON public.posts(user_id, created_at DESC);
CREATE INDEX idx_posts_campaign ON public.posts(campaign_id);
CREATE INDEX idx_post_media_post ON public.post_media(post_id);
CREATE INDEX idx_comments_post ON public.comments(post_id);
CREATE INDEX idx_reactions_post ON public.reactions(post_id);
CREATE INDEX idx_referrals_referrer ON public.referrals(referrer_id);
CREATE INDEX idx_points_ledger_user ON public.points_ledger(user_id, created_at DESC);
CREATE INDEX idx_activities_type_active ON public.activities(type, is_active);
CREATE INDEX idx_notifications_user_unread ON public.notifications(user_id, is_read);

-- =========================================================
-- 4. SEGURIDAD: ROW LEVEL SECURITY (RLS) (RNF-02)
-- =========================================================
-- Activar RLS en todas las tablas
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_intentions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.points_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reward_redemptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- --- POLÍTICAS DE EJEMPLO (Ajustar según lógica de negocio final) ---

-- Perfiles: Todos pueden ver perfiles, pero solo el dueño o admin puede editar
CREATE POLICY "Perfiles son visibles para todos" ON public.profiles FOR SELECT USING (TRUE);
CREATE POLICY "Usuarios pueden actualizar su propio perfil" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Posts: Todos pueden ver posts publicados. Solo el autor o admin puede crear/editar/borrar.
CREATE POLICY "Posts publicados son visibles para todos" ON public.posts FOR SELECT USING (is_published = TRUE);
CREATE POLICY "Usuarios pueden crear sus propios posts" ON public.posts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Usuarios pueden actualizar/borrar sus propios posts" ON public.posts FOR DELETE USING (auth.uid() = user_id);

-- Comentarios: Todos pueden ver, usuarios autenticados pueden comentar, solo el autor borra.
CREATE POLICY "Comentarios visibles para todos" ON public.comments FOR SELECT USING (TRUE);
CREATE POLICY "Usuarios autenticados pueden comentar" ON public.comments FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Usuarios pueden borrar sus propios comentarios" ON public.comments FOR DELETE USING (auth.uid() = user_id);

-- Reacciones: Visible para todos, insertar solo propio.
CREATE POLICY "Reacciones visibles para todos" ON public.reactions FOR SELECT USING (TRUE);
CREATE POLICY "Usuarios pueden reaccionar" ON public.reactions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Usuarios pueden quitar sus reacciones" ON public.reactions FOR DELETE USING (auth.uid() = user_id);

-- Referidos: Solo el referidor o admin puede ver sus referidos.
CREATE POLICY "Usuarios ven sus propios referidos" ON public.referrals FOR SELECT USING (auth.uid() = referrer_id);
CREATE POLICY "Usuarios pueden crear referidos" ON public.referrals FOR INSERT WITH CHECK (auth.uid() = referrer_id);

-- Intenciones de Crédito: Solo el propio usuario o admin puede verlas.
CREATE POLICY "Usuarios ven sus propias intenciones de crédito" ON public.credit_intentions FOR SELECT USING (auth.uid() = profile_id);
CREATE POLICY "Usuarios pueden solicitar crédito" ON public.credit_intentions FOR INSERT WITH CHECK (auth.uid() = profile_id);

-- Notificaciones: Solo el dueño puede ver y marcar como leídas.
CREATE POLICY "Usuarios ven sus propias notificaciones" ON public.notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Usuarios pueden actualizar sus notificaciones" ON public.notifications FOR UPDATE USING (auth.uid() = user_id);
-- =========================================================
-- 5. TRIGGER AUTOMÁTICO PARA CREAR PERFIL
-- =========================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();