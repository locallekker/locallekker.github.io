export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "13.0.5"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      memberships: {
        Row: {
          created_at: string
          gateway: string | null
          role: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          gateway?: string | null
          role: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          gateway?: string | null
          role?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      payment_schedules: {
        Row: {
          amount: number
          created_at: string | null
          failure_count: number
          id: string
          is_active: boolean
          last_attempt_date: string | null
          next_payment_date: string
          payment_method: string
          payment_method_id: string | null
          subscription_id: string
          updated_at: string | null
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string | null
          failure_count?: number
          id?: string
          is_active?: boolean
          last_attempt_date?: string | null
          next_payment_date: string
          payment_method: string
          payment_method_id?: string | null
          subscription_id: string
          updated_at?: string | null
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string | null
          failure_count?: number
          id?: string
          is_active?: boolean
          last_attempt_date?: string | null
          next_payment_date?: string
          payment_method?: string
          payment_method_id?: string | null
          subscription_id?: string
          updated_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      processed_bills: {
        Row: {
          created_at: string | null
          discount_amount: number
          discount_id: string
          discounted_total: number
          id: string
          image_url: string | null
          original_total: number
          partner_id: string
          processed_at: string | null
          receipt_data: Json
          updated_at: string | null
          user_id: string
        }
        Insert: {
          created_at?: string | null
          discount_amount: number
          discount_id: string
          discounted_total: number
          id?: string
          image_url?: string | null
          original_total: number
          partner_id: string
          processed_at?: string | null
          receipt_data: Json
          updated_at?: string | null
          user_id: string
        }
        Update: {
          created_at?: string | null
          discount_amount?: number
          discount_id?: string
          discounted_total?: number
          id?: string
          image_url?: string | null
          original_total?: number
          partner_id?: string
          processed_at?: string | null
          receipt_data?: Json
          updated_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          category: string | null
          city: string | null
          contact: string | null
          created_at: string
          date_of_birth: string | null
          email: string | null
          ethnicity: string | null
          gender: string | null
          id: string
          name: string | null
          province: string | null
          role: string | null
          street: string | null
          suburb: string | null
          surname: string | null
          updated_at: string
        }
        Insert: {
          category?: string | null
          city?: string | null
          contact?: string | null
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          ethnicity?: string | null
          gender?: string | null
          id: string
          name?: string | null
          province?: string | null
          role?: string | null
          street?: string | null
          suburb?: string | null
          surname?: string | null
          updated_at?: string
        }
        Update: {
          category?: string | null
          city?: string | null
          contact?: string | null
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          ethnicity?: string | null
          gender?: string | null
          id?: string
          name?: string | null
          province?: string | null
          role?: string | null
          street?: string | null
          suburb?: string | null
          surname?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      user_qr_codes: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          is_active: boolean
          name: string | null
          qr_code: string
          surname: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          expires_at: string
          id?: string
          is_active?: boolean
          name?: string | null
          qr_code: string
          surname?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          is_active?: boolean
          name?: string | null
          qr_code?: string
          surname?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      users: {
        Row: {
          created_at: string
          email: string | null
          id: string
        }
        Insert: {
          created_at?: string
          email?: string | null
          id: string
        }
        Update: {
          created_at?: string
          email?: string | null
          id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      activate_qr_after_payment: {
        Args: { p_amount: number; p_plan_type: string; p_user_id: string }
        Returns: boolean
      }
      complete_business_profile: {
        Args: { payload: Json }
        Returns: Json
      }
      complete_merchant_signup: {
        Args: { payload: Json }
        Returns: Json
      }
      create_staff_admin: {
        Args: { payload: Json }
        Returns: Json
      }
      disable_auto_renewal: {
        Args: { p_user_id: string }
        Returns: boolean
      }
      enable_auto_renewal: {
        Args: {
          p_payment_method: string
          p_payment_method_id: string
          p_user_id: string
        }
        Returns: boolean
      }
      get_admin_dashboard: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
      get_subscription_status: {
        Args: { p_user_id: string }
        Returns: {
          auto_renew: boolean
          days_until_renewal: number
          has_active_qr: boolean
          next_payment_date: string
          payment_overdue: boolean
          qr_expires_at: string
          subscription_end_date: string
          subscription_status: string
        }[]
      }
      get_user_bill_statistics: {
        Args: { user_uuid: string }
        Returns: {
          most_used_partner: string
          total_bills: number
          total_saved: number
          total_spent: number
        }[]
      }
      process_automatic_payment: {
        Args: { p_user_id: string }
        Returns: boolean
      }
      process_automatic_payments: {
        Args: Record<PropertyKey, never>
        Returns: {
          amount: number
          error_message: string
          subscription_id: string
          success: boolean
          user_id: string
        }[]
      }
      schedule_automatic_payment: {
        Args: {
          p_amount: number
          p_payment_method: string
          p_payment_method_id: string
          p_subscription_id: string
          p_user_id: string
        }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
