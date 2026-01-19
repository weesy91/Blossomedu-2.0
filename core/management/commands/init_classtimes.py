from django.core.management.base import BaseCommand
from django.utils.dateparse import parse_time
from datetime import datetime, timedelta, time
from core.models import ClassTime, Branch

class Command(BaseCommand):
    help = '援щЦ 諛??낇빐 ?섏뾽 ?쒓컙???곗씠?곕? ?쇨큵 ?앹꽦?⑸땲??'

    def add_arguments(self, parser):
        # 湲곗〈 ?곗씠?곕? 吏?곌퀬 ?덈줈 留뚮뱾吏 ?щ?瑜??듭뀡?쇰줈 諛쏆쓬
        parser.add_argument(
            '--clear',
            action='store_true',
            help='湲곗〈 ?쒓컙???곗씠?곕? 紐⑤몢 ??젣?섍퀬 ?덈줈 ?앹꽦?⑸땲??',
        )

    def handle(self, *args, **options):
        # 1. 湲곗〈 ?곗씠????젣 ?듭뀡 ?뺤씤
        if options['clear']:
            self.stdout.write(self.style.WARNING('湲곗〈 ?쒓컙???곗씠?곕? ??젣?섎뒗 以?..'))
            ClassTime.objects.all().delete()
            self.stdout.write(self.style.SUCCESS('??젣 ?꾨즺.'))

        # 2. ?곸슜???붿씪 諛?吏???ㅼ젙
        days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        branches = Branch.objects.all()

        if not branches.exists():
            self.stdout.write(self.style.ERROR('?깅줉??吏??Branch)???놁뒿?덈떎. 吏?먯쓣 癒쇱? ?앹꽦?댁＜?몄슂.'))
            return

        total_created = 0

        # 3. ?쒓컙 ?앹꽦 濡쒖쭅 ?뺤쓽
        for branch in branches:
            self.stdout.write(f"[{branch.name}] ?쒓컙???앹꽦 ?쒖옉...")
            
            for day in days:
                # ==========================================
                # A. 援щЦ (Syntax) ?쒓컙???앹꽦
                # ==========================================
                # 洹쒖튃 1: ?ㅼ쟾 (09:00 ?쒖옉 ~ 12:20 ?쒖옉??留덉?留? -> 媛꾧꺽 40遺?                # 洹쒖튃 2: ?ㅽ썑 (13:20 ?쒖옉 ~ 20:40 ?쒖옉??留덉?留? -> 媛꾧꺽 40遺?                
                # ?ㅼ쟾 猷⑦봽
                current_time = datetime.strptime("09:00", "%H:%M")
                morning_end_limit = datetime.strptime("12:20", "%H:%M") # 12:20 ?쒖옉??留됲???                
                while current_time <= morning_end_limit:
                    start = current_time.time()
                    end_dt = current_time + timedelta(minutes=40)
                    end = end_dt.time()
                    
                    self.create_class_time(branch, day, start, end, "\uad6c\ubb38")
                    current_time = end_dt # 40遺??ㅺ? ?ㅼ쓬 ????쒖옉

                # ?ㅽ썑 猷⑦봽
                current_time = datetime.strptime("13:20", "%H:%M") # ?먯떖?쒓컙 20遺????쒖옉
                afternoon_end_limit = datetime.strptime("20:40", "%H:%M") # 20:40 ?쒖옉??留됲???
                while current_time <= afternoon_end_limit:
                    start = current_time.time()
                    end_dt = current_time + timedelta(minutes=40)
                    end = end_dt.time()

                    self.create_class_time(branch, day, start, end, "\uad6c\ubb38")
                    current_time = end_dt

                # ==========================================
                # B. ?낇빐 (Reading) ?쒓컙???앹꽦
                # ==========================================
                # 洹쒖튃: 09:00 ?쒖옉 ~ 20:30 ?쒖옉??留덉?留?-> 媛꾧꺽 30遺?                
                current_time = datetime.strptime("09:00", "%H:%M")
                reading_end_limit = datetime.strptime("20:30", "%H:%M")

                while current_time <= reading_end_limit:
                    start = current_time.time()
                    end_dt = current_time + timedelta(minutes=30)
                    end = end_dt.time()

                    self.create_class_time(branch, day, start, end, "\ub3c5\ud574")
                    current_time = end_dt

        self.stdout.write(self.style.SUCCESS('紐⑤뱺 ?쒓컙???앹꽦???꾨즺?섏뿀?듬땲??'))
    def create_class_time(self, branch, day, start, end, type_name):
        """중복 방지하며 ClassTime 생성"""
        # 이름은 "구문 09:00" 형식으로 자동 생성 (관리 편의용)
        name = f"{type_name} {start.strftime('%H:%M')}"
        class_type = (
            ClassTime.ClassTypeChoices.SYNTAX
            if type_name == "\uad6c\ubb38"
            else ClassTime.ClassTypeChoices.READING
        )

        obj, created = ClassTime.objects.get_or_create(
            branch=branch,
            day=day,
            start_time=start,
            end_time=end,
            defaults={'name': name, 'class_type': class_type}
        )
        if not created:
            updates = {}
            if type_name in (obj.name or '') and obj.class_type != class_type:
                updates['class_type'] = class_type
            if not obj.name:
                updates['name'] = name
            if updates:
                for key, value in updates.items():
                    setattr(obj, key, value)
                obj.save(update_fields=list(updates.keys()))
        if created:
            # print(f"  + 생성: {branch} {day} {name}") # 업무 로그가 많으면 주석 처리
            pass
