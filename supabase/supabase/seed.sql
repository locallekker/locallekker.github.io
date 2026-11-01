-- Create the missing try_cast_double function
CREATE OR REPLACE FUNCTION public.try_cast_double(input_text text)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    BEGIN
        RETURN input_text::double precision;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RETURN NULL;
    END;
END;
$$;