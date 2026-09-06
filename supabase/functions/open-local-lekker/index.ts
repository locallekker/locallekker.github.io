import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const deepLink = "locallekker://auth/callback?type=signup_reminder"
const androidIntent =
  "intent://auth/callback?type=signup_reminder#Intent;scheme=locallekker;package=com.locallekker.app;end"
const webSignupReminderUrl = "https://locallekker.github.io/?type=signup_reminder"

serve(async (req) => {
  const url = new URL(req.url)
  const action = url.searchParams.get("action")
  const trackingToken = url.searchParams.get("token")
  const userAgent = req.headers.get("user-agent") ?? ""
  const isAndroid = /Android/i.test(userAgent)
  const isIos = /iPhone|iPad|iPod/i.test(userAgent)
  const isMobile = isAndroid || /iPhone|iPad|iPod/i.test(userAgent)
  const appTarget = isAndroid ? androidIntent : isIos ? webSignupReminderUrl : deepLink

  if (!action && !trackingToken) {
    return new Response(null, {
      status: 302,
      headers: { Location: appTarget, "Cache-Control": "no-store" },
    })
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  if (!trackingToken || (action !== "open" && action !== "opt_out")) {
    return new Response("This reminder link is invalid.", { status: 400 })
  }

  if (action === "open" && !isMobile) {
    return new Response(null, {
      status: 302,
      headers: { Location: appTarget, "Cache-Control": "no-store" },
    })
  }

  const { data: recorded, error } = await supabase.rpc(
    "record_member_signup_reminder_event",
    {
      p_tracking_token: trackingToken,
      p_event: action,
    },
  )

  if (error || recorded !== true) {
    console.error("Could not record signup reminder event:", error?.message)
    return new Response("This reminder link is invalid or has expired.", { status: 404 })
  }

  if (action === "opt_out") {
    return new Response(
      "You have opted out of Local Lekker signup reminders. You will not receive further signup reminder emails.",
      { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } },
    )
  }

  return new Response(null, {
    status: 302,
    headers: {
      Location: appTarget,
      "Cache-Control": "no-store",
    },
  })
})
