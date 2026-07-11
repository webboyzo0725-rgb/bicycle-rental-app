import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export const configurationError = !url || !key;

export const supabase = createClient(
  url || "https://example.supabase.co",
  key || "missing-key",
  { auth: { persistSession: false } },
);

export async function rpc<T>(name: string, params: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(name, params);
  if (error) throw new Error(error.message);
  return data as T;
}
