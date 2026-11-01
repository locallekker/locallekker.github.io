-- Trigger: Automatically notify all admins when a new TP inquiry is submitted
--
-- This creates a notification in the notifications table for each admin user
-- when a row is inserted into tp_inquiries. The existing database webhook
-- on notifications INSERT will then send FCM push notifications to admin devices.
--
-- Run this in the Supabase SQL Editor.

CREATE OR REPLACE FUNCTION public.notify_admins_on_tp_inquiry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.notifications (user_id, title, message, type, data, is_read, created_at)
  SELECT
    p.id,
    'New Trusted Partner Inquiry',
    NEW.name || ' ' || NEW.surname || ' (' || NEW.business_name || ') wants to become a Trusted Partner',
    'tp_inquiry',
    jsonb_build_object(
      'inquiry_id', NEW.id,
      'business_name', NEW.business_name,
      'business_type', COALESCE(NEW.business_type, 'Not specified'),
      'email', NEW.email,
      'contact_number', COALESCE(NEW.contact_number, 'Not provided'),
      'city', COALESCE(NEW.city, 'Not specified')
    ),
    false,
    now()
  FROM public.profiles p
  WHERE p.role = 'admin';

  RETURN NEW;
END;
$$;

-- Create trigger on tp_inquiries table
DROP TRIGGER IF EXISTS on_tp_inquiry_insert_notify_admins ON public.tp_inquiries;

CREATE TRIGGER on_tp_inquiry_insert_notify_admins
  AFTER INSERT ON public.tp_inquiries
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_admins_on_tp_inquiry();
