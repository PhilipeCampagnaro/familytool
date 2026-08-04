/// Outbound mail.
///
/// Resend, matching the sender the old web app already used. Without
/// RESEND_API_KEY and APORAH_MAIL_FROM this logs the message and honestly
/// reports that nothing was sent, so the caller can surface "Link kopieren" as
/// the fallback instead of claiming an e-mail is on its way.

export type MailResult = { sent: boolean; reason?: string };

export async function sendMail(
  to: string,
  subject: string,
  html: string,
): Promise<MailResult> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("APORAH_MAIL_FROM");

  if (!apiKey || !from) {
    console.log(`[mail] not configured, skipping send to ${to}: ${subject}`);
    return { sent: false, reason: "mail_not_configured" };
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from, to, subject, html }),
  });

  if (!res.ok) {
    console.error(`[mail] send failed (${res.status}): ${await res.text()}`);
    return { sent: false, reason: "mail_send_failed" };
  }

  return { sent: true };
}

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
