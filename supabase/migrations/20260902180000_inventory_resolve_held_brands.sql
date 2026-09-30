-- Resolve the 8 brands held back by 20260902170000, and fix 6 broken item names.
--
-- The previous migration left 8 rows' brand/variety NULL because I could not
-- tell whether a word was a brand or a descriptor. That was over-caution: the
-- catalogue's own naming pattern already answers it. Each of these words sits
-- in exactly the slot every confirmed brand occupies for that product family:
--
--   فلتر قهوة <brand>  →  انيشن · ماليتا · مستر كوفي · بن
--   شيكولاتة <brand>   →  باسلات · باتشي · ديلوكس
--   زعفران <brand>     →  اسيانا · سوبر
--   سكر … <brand> …    →  «سكر اصابع الراحة ابيض» vs «سكر حاجة أصابع ابيض»
--   هيل <brand>        →  ابو دلة · الدلة الذهبية · ماس
--   «- <name>» trailing →  الضيف, as in «معمول التمر - الضيف»
--
-- «ديلوكس» is a brand here even though the same word is a descriptor in
-- «مكسرات مشكل ديلوكس» -- position in the name is what distinguishes them.

UPDATE "public"."inventory" SET brand = 'بن'
  WHERE "id" = '770f3b45-25b7-4d21-bea0-ae8075af8471';  -- فلتر قهوة بن - 100 حبة
UPDATE "public"."inventory" SET brand = 'ديلوكس'
  WHERE "id" = '5a0d295c-58d5-45c0-8612-f1e16290a579';  -- شيكولاتة ديلوكس
UPDATE "public"."inventory" SET brand = 'فلة', variety = 'مشكل ديلوكس مملح'
  WHERE "id" = 'eda47a0a-0a4f-48a5-880e-47954732ff78';  -- مكسرات - مشكل ديلوكس مملح فلة
UPDATE "public"."inventory" SET brand = 'الضيف', variety = 'خلاص القصيم فاكيوم'
  WHERE "id" = '516fa9b8-0b9e-4139-9d8f-2a19ee89a5fb';  -- خلاص القصيم فاكيوم - 500 جم - الضيف
UPDATE "public"."inventory" SET brand = 'سوبر'
  WHERE "id" = '36333d1c-5111-4454-8981-fe6ec40a6e26';  -- زعفران سوبر - 10 جم
UPDATE "public"."inventory" SET brand = 'حاجة', variety = 'أصابع أبيض'
  WHERE "id" = '19db67c3-9ea7-44d3-a0e2-90488d7e8b7f';  -- سكر حاجة أصابع ابيض - 400 جم
UPDATE "public"."inventory" SET brand = 'ماس', variety = 'هندي'
  WHERE "id" = 'd5ee43a7-97ef-49b3-9510-7adb1b5a135f';  -- هيل هندي ماس 250 جم
UPDATE "public"."inventory" SET brand = 'أبو حصان', variety = 'هرري'
  WHERE "id" = '9434bd8c-d10b-4570-8cb9-7bc93e201a4f';  -- بن هرري ابو حصان - 1 كجم

-- ── Name repairs ────────────────────────────────────────────────────────────
--
-- These edit item_name, which every migration so far has deliberately avoided.
-- The standing rule is that names must not be RESTRUCTURED -- the piece size
-- stays inside the name, and stripping it would break AI matching, which reads
-- item_name and nothing else. Repairing a broken character is the opposite: a
-- customer writing «قهوة لدن 500 جم» currently cannot match a row that says
-- «500 حم», so these fixes make matching strictly better, not worse.
--
-- Each is a single mangled character or a doubled space. No word is added,
-- removed, or reordered. Uniqueness is unaffected: all 195 names stay distinct.
-- To reverse, swap the two strings in any statement below.

UPDATE "public"."inventory" SET item_name = 'قهوة لدن 500 جم'
  WHERE "id" = '21c9bfbf-3c8e-434d-9bb3-604ce89882b4';  -- كان: «500 حم»
UPDATE "public"."inventory" SET item_name = 'مكسرات مشكلة - 1 كجم'
  WHERE "id" = 'e34ab90b-288c-4b34-9b94-07f7e15e92fe';  -- كان: «ا كجم»
UPDATE "public"."inventory" SET item_name = 'نسكويك بودرة كبير - 1 كيلو'
  WHERE "id" = '197a9a8f-bb0a-40fa-8eb3-47ad647d689f';  -- كان: «ا كيلو»
UPDATE "public"."inventory" SET item_name = 'شاي كريشو مغلف 100 حبة'
  WHERE "id" = 'f5ea5805-939c-471f-a1b1-1c3735904704';  -- كان: «100 حبه»
UPDATE "public"."inventory" SET item_name = 'تمر سكري جلاكسي 39/25'
  WHERE "id" = '5e32c5a7-6ca2-4e9f-91e4-980de15b98e4';  -- كان: مسافة مزدوجة
UPDATE "public"."inventory" SET item_name = 'مياة نوفا 1.50 لتر - 12 حبة'
  WHERE "id" = 'f431b7ee-ad1a-4520-9766-0c6f78bcb88d';  -- كان: مسافة مزدوجة

-- NOT changed: the category and 8 names spell water «مياة» where standard
-- Arabic is «مياه». That is a spelling variant in common use, not a broken
-- character, and rewriting it would be restructuring. The right home for the
-- variant customers actually type is the `aliases` column, still unpopulated.
