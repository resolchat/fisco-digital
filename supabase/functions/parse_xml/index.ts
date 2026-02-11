import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { XMLParser } from "https://esm.sh/fast-xml-parser@4.2.5";

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_"
});

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  try {
    const contentType = req.headers.get('content-type') || '';
    let xmlData = '';

    if (contentType.includes('multipart/form-data')) {
      const formData = await req.formData();
      const file = formData.get('file');
      if (!file || typeof file === 'string') {
        return new Response('File not found', { status: 400 });
      }
      xmlData = await file.text();
    } else {
      xmlData = await req.text();
    }

    if (!xmlData) {
      return new Response('Empty body', { status: 400 });
    }

    const jsonObj = parser.parse(xmlData);
    
    // Basic extraction logic (simplified for NFe/CTe)
    // You would expand this to handle specific tagging of NFe vs CTe
    let result = {
      tipo: 'outros',
      chave: '',
      numero: '',
      serie: '',
      emitente: '',
      destinatario: '',
      valor: 0,
      data_emissao: null
    };

    const nfe = jsonObj.nfeProc?.NFe?.infNFe || jsonObj.NFe?.infNFe;
    const cte = jsonObj.cteProc?.CTe?.infCte || jsonObj.CTe?.infCte;

    if (nfe) {
        result.tipo = 'nfe';
        result.chave = nfe['@_Id']?.replace('NFe', '') || '';
        result.numero = nfe.ide?.nNF;
        result.serie = nfe.ide?.serie;
        result.emitente = nfe.emit?.xNome;
        result.destinatario = nfe.dest?.xNome;
        result.valor = parseFloat(nfe.total?.ICMSTot?.vNF || '0');
        result.data_emissao = nfe.ide?.dhEmi || nfe.ide?.dEmi;
    } else if (cte) {
        result.tipo = 'cte';
        result.chave = cte['@_Id']?.replace('CTe', '') || '';
        result.numero = cte.ide?.nCT;
        result.serie = cte.ide?.serie;
        result.emitente = cte.emit?.xNome;
        result.destinatario = cte.rem?.xNome || cte.dest?.xNome; // Simplification
        result.valor = parseFloat(cte.vPrest?.vTPrest || '0');
        result.data_emissao = cte.ide?.dhEmi;
    }

    return new Response(JSON.stringify({ data: jsonObj, parsed: result }), {
      headers: { "Content-Type": "application/json" },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
