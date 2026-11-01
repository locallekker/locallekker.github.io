-- Find the actual sequence name for notifications table
SELECT 
    pg_get_serial_sequence('notifications', 'id') as sequence_name;

-- Alternative: List all sequences
SELECT 
    schemaname,
    sequencename
FROM pg_sequences
WHERE sequencename LIKE '%notification%';
