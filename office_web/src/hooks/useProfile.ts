import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { mapProfile } from '../lib/mappers';
import { useAuth } from './useAuth';

export function useProfile() {
  const { session } = useAuth();
  const userId = session?.user.id;

  return useQuery({
    queryKey: ['profile', userId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name, phone, role, is_approved')
        .eq('id', userId)
        .single();
      if (error) throw new Error(error.message);
      return mapProfile(data);
    },
    enabled: !!userId,
  });
}
