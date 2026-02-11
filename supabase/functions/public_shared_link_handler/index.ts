import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.21.0"

serve(async (req) => {
    // e.g. POST /public_shared_link_handler { token: "..." }
    // or GET /public_shared_link_handler?token=...

    const url = new URL(req.url);
    const token = url.searchParams.get('token');

    if (!token) {
        return new Response('Missing token', { status: 400 });
    }

    // Initialize Supabase Client with Service Role Key (to bypass RLS for the link check)
    // SECURITY: This function must be deployed with SUPABASE_SERVICE_ROLE_KEY env var
    const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 1. Validate Token
    const { data: link, error } = await supabaseAdmin
        .from('shared_links')
        .select('*, documents(*)')
        .eq('token', token)
        .single();

    if (error || !link) {
        return new Response('Invalid or expired link', { status: 404 });
    }

    if (link.revoked_at) {
        return new Response('Link revoked', { status: 403 });
    }

    if (link.expires_at && new Date(link.expires_at) < new Date()) {
        return new Response('Link expired', { status: 410 });
    }

    // 2. Return Data or File
    // usage: ?token=...&action=download
    const action = url.searchParams.get('action');

    if (action === 'download') {
        if (!link.permissions?.download) {
            return new Response('Download permission denied', { status: 403 });
        }

        // Generate Signed URL for the actual file
        // Assuming we want to serve the PDF
        const pdfPath = link.documents.pdf_url;
        if (!pdfPath) {
            return new Response('Document has no PDF', { status: 404 });
        }

        // We need to extract bucket and path from the stored URL or path
        // stored: "bucket/path/to/file.pdf" ? Depend on implementation.
        // Let's assume pdf_url IS the path in 'documents' bucket for simplicity, or we parse it.

        const { data: signed, error: signError } = await supabaseAdmin
            .storage
            .from('documents')
            .createSignedUrl(pdfPath, 60); // 1 minute link

        if (signError) {
            return new Response('Error generating download link', { status: 500 });
        }

        // Redirect to signed URL
        return Response.redirect(signed.signedUrl);
    }

    // Default: Return Document Metadata for the Viewer UI
    return new Response(JSON.stringify({
        document: {
            numero: link.documents.numero,
            serie: link.documents.serie,
            data: link.documents.emissao_data,
            valor: link.documents.valor_total,
            status: link.documents.status
        },
        permissions: link.permissions
    }), {
        headers: { "Content-Type": "application/json" },
    })
});
