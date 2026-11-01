-- Diagnostic query to check current deal image RLS policies
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual::text as using_expression,
    with_check::text as with_check_expression,
    CASE 
        WHEN policyname LIKE '%Admin%' AND cmd = 'SELECT' THEN 'Admin view policy'
        WHEN policyname LIKE '%Member%' AND cmd = 'SELECT' THEN 'Member view policy'
        WHEN policyname LIKE '%Trusted partner%' AND cmd = 'SELECT' THEN 'TP view policy'
        WHEN policyname LIKE '%Upload%' AND cmd = 'INSERT' THEN 'Upload policy'
        ELSE 'Other'
    END as policy_purpose
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND (policyname LIKE '%deal image%' OR policyname LIKE '%Admins%' OR policyname LIKE '%Members%' OR policyname LIKE '%Trusted%')
  AND bucket_id = 'business-bills'
ORDER BY cmd DESC, policyname;

-- Check for duplicate or conflicting policies
SELECT 
    cmd,
    COUNT(*) as policy_count,
    STRING_AGG(policyname, ', ') as policies
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND cmd = 'SELECT'
  AND bucket_id IN (SELECT id FROM storage.buckets WHERE name = 'business-bills')
GROUP BY cmd;
