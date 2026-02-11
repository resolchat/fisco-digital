import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.21.0"

// Types (simplified)
interface AutomationRule {
    id: string;
    trigger_filters: any;
    action_type: string;
    action_config: any;
}

serve(async (req) => {
    // This function should be triggered via Cron (e.g., every 1 min) or Webhook

    const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 1. Fetch pending events
    const { data: events, error } = await supabaseAdmin
        .from('automation_queue')
        .select('*')
        .eq('status', 'pending')
        .limit(10); // Batch size

    if (error) {
        return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    }

    if (!events || events.length === 0) {
        return new Response(JSON.stringify({ message: 'No pending events' }), { status: 200 });
    }

    const results = [];

    for (const event of events) {
        try {
            // Mark as processing
            await supabaseAdmin.from('automation_queue').update({ status: 'processing' }).eq('id', event.id);

            // Fetch matching rules
            const { data: rules } = await supabaseAdmin
                .from('automation_rules')
                .select('*')
                .eq('company_id', event.company_id)
                .eq('trigger_type', event.event_type)
                .eq('ativo', true);

            if (rules) {
                for (const rule of rules) {
                    // Apply Filters (simplistic implementation)
                    // In a real app, use a library like sieve/json-logic
                    const matches = checkFilters(event.payload, rule.trigger_filters);

                    if (matches) {
                        await executeAction(supabaseAdmin, rule, event);
                    }
                }
            }

            // Mark as completed
            await supabaseAdmin.from('automation_queue').update({
                status: 'completed',
                processed_at: new Date()
            }).eq('id', event.id);

            results.push({ id: event.id, status: 'ok' });

        } catch (err) {
            // Mark as error
            await supabaseAdmin.from('automation_queue').update({
                status: 'error',
                error_log: err.message
            }).eq('id', event.id);
            results.push({ id: event.id, status: 'error', error: err.message });
        }
    }

    return new Response(JSON.stringify({ processed: results }), {
        headers: { "Content-Type": "application/json" },
    });
});

function checkFilters(payload: any, filters: any): boolean {
    if (!filters || Object.keys(filters).length === 0) return true;

    for (const key of Object.keys(filters)) {
        if (payload[key] != filters[key]) { // Loose equality for simplicity
            return false;
        }
    }
    return true;
}

async function executeAction(supabase: any, rule: AutomationRule, event: any) {
    // Implement actions
    if (rule.action_type === 'criar_entrega') {
        // Example: Create delivery for document
        // Needs proper mapping
        if (event.event_type === 'documento_criado' && rule.action_config.auto_assign) {
            // Create delivery logic...
        }
    } else if (rule.action_type === 'webhook') {
        // Add to webhooks_outbox
        await supabase.from('webhooks_outbox').insert({
            company_id: event.company_id,
            rule_id: rule.id,
            payload_json: event.payload
        });
    }
    // ... other actions
}
