// Public CRM photo only. Preparation happens in the extension worker, outside WhatsApp's page CSP.
export async function preparePropertyPhoto(url) {
  let parsed;
  try { parsed = new URL(url); } catch { throw new Error("preview_image_invalid"); }
  if (parsed.protocol !== 'https:' || parsed.username || parsed.password) throw new Error('preview_image_invalid');
  const abort = new AbortController();
  const timeout = setTimeout(() => abort.abort(), 12000);
  let bitmap;
  try {
    const response = await fetch(parsed.href, {credentials:'omit', referrerPolicy:'no-referrer', signal:abort.signal});
    if (!response.ok || !/^image\/(jpeg|png|webp)(;|$)/i.test(response.headers.get('content-type') || '')) throw new Error('preview_image_failed');
    const blob = await response.blob();
    if (blob.size > 5 * 1024 * 1024) throw new Error('preview_image_invalid');
    bitmap = await createImageBitmap(blob);
    if (bitmap.width < 300 || bitmap.height < 1) throw new Error('preview_image_invalid');
    const scale = Math.min(320 / bitmap.width, 320 / bitmap.height);
    const canvas = new OffscreenCanvas(Math.max(1,Math.round(bitmap.width*scale)),Math.max(1,Math.round(bitmap.height*scale)));
    canvas.getContext('2d').drawImage(bitmap,0,0,canvas.width,canvas.height);
    const jpeg = await canvas.convertToBlob({type:'image/jpeg',quality:.8});
    const bytes = new Uint8Array(await jpeg.arrayBuffer());
    let binary = '';
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary);
  } catch (error) {
    if (abort.signal.aborted) throw new Error('preview_timeout');
    throw new Error(error.message === 'preview_image_invalid' ? error.message : 'preview_image_failed');
  } finally { clearTimeout(timeout); bitmap?.close(); }
}
