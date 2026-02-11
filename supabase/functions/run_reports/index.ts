import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.21.0"

serve(async (req) => {
    // Triggered by Cron (e.g. daily midnight)

    const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const now = new Date();

    // Find reports due
    const { data: reports, error } = await supabaseAdmin
        .from('scheduled_reports')
        .select('*')
        .eq('ativo', true)
        .lte('next_run_at', now.toISOString());

    if (error) return new Response(error.message, { status: 500 });

    if (!reports?.length) return new Response('No reports due', { status: 200 });

    for (const report of reports) {
        try {
            // Generate Data (Example: Export Documents)
            // In real app: Construct query based on 'filtros'
            const { data: docs } = await supabaseAdmin
                .from('documents')
                .select('*')
                .eq('company_id', report.company_id)
                .limit(100); // Limit for safety

            // Convert to CSV
            const csvLines = [];
            if (docs && docs.length > 0) {
                const headers = Object.keys(docs[0]).join(',');
                csvLines.push(headers);
                for (const doc of docs) {
                    const values = Object.values(doc).map(v => `"${v}"`).join(',');
                    csvLines.push(values);
                }
            }
            const csvContent = csvLines.join('\n');

            // Upload to Storage
            const fileName = `${report.company_id}/reports/${report.id}_${Date.now()}.csv`;
            const { error: uploadError } = await supabaseAdmin.storage
                .from('reports')
                .upload(fileName, csvContent, { contentType: 'text/csv' });

            if (uploadError) throw uploadError;

            // Log Run
            await supabaseAdmin.from('report_runs').insert({
                company_id: report.company_id,
                report_id: report.id,
                status: 'success',
                file_url: fileName
            });

            // Update Next Run
            const nextDate = new Date(now);
            if (report.periodicidade === 'daily') nextDate.setDate(nextDate.getDate() + 1);
            if (report.periodicidade === 'weekly') nextDate.setDate(nextDate.getDate() + 7);
            if (report.periodicidade === 'monthly') nextDate.setMonth(nextDate.getMonth() + 1);

            await supabaseAdmin.from('scheduled_reports')
                .update({ next_run_at: nextDate })
                .eq('id', report.id);

        } catch (err) {
            console.error(err);
            await supabaseAdmin.from('report_runs').insert({
                company_id: report.company_id,
                report_id: report.id,
                status: 'failed: ' + err.message
            });
        }
    }

    return new Response(JSON.stringify({ processed: reports.length }), {
        headers: { "Content-Type": "application/json" },
    });
});
